require 'tempfile'
require 'concurrent'

class DakeExecutor
  def initialize(analyzer, dake_db, dep_graph, jobs)
    @analyzer = analyzer
    @dake_db = dake_db
    @dep_graph = dep_graph
    @complete_dep_steps = Hash.new(0)
    @async = (jobs ? true : false)
    @pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: jobs,
        max_queue: 0 # unbounded work queue
    ) if @async
  end

  def execute(rebuild_set, dry_run=false, log=false)
    if rebuild_set.empty?
      STDERR.puts "Nothing to be done.".colorize(:green)
      return
    end
    if @async
      dep_map = Hash.new
      rebuild_set.each do |step|
        dep_set = @dep_graph.dep_step[step]
        next if dep_set.empty?
        dep_map[step] = dep_set & rebuild_set
      end

      queue = Queue.new
      error_queue = Queue.new
      error_steps = Set.new

      error_thr = Thread.new do
        while error = error_queue.deq
          if error.is_a? Exception
            STDERR.puts "#{error.class}: #{error.message}".colorize(:red)
            STDERR.puts "Continue to execute other Step(s)".colorize(:red)
            STDERR.puts "To Force Quitting: Press Ctrl + C".colorize(:red)
          end
        end
      end

      lock = Concurrent::ReadWriteLock.new
      @dep_graph.leaf_step.each { |step| queue << step if rebuild_set.include? step }

      while next_step = queue.deq
        @pool.post(next_step) do |step|
          lock.acquire_read_lock
          error_step = error_steps.include? step
          lock.release_read_lock
          if error_step
            line, column = @analyzer.step_line_and_column step
            msg = "Step(#{step.object_id}) defined in #{step.src_file} at #{line}:#{column} " +
                  "skipped due to prerequisite step(s) error."
            error_queue << Exception.new(msg)
          else
            execute_step(step, dry_run, log)
          end
          lock.acquire_write_lock
          dep_map.delete step
          if dep_map.empty?
            queue.close
          else
            @dep_graph.succ_step[step].each do |succ|
              next unless dep_map[succ]
              dep_map[succ].delete step
              if dep_map[succ].empty?
                queue << succ
              elsif dep_map[succ].all? { |dep_step| error_steps.include? dep_step }
                error_steps << succ
                queue << succ
              end
            end
          end
          lock.release_write_lock
        rescue Exception => e
          error_queue << e
          lock.acquire_write_lock
          error_steps << step
          dep_map.delete step
          if dep_map.empty?
            queue.close
          else
            @dep_graph.succ_step[step].each do |succ|
              if dep_map[succ].all? { |dep_step| error_steps.include? dep_step }
                error_steps << succ
                queue << succ
              end
            end
          end
          lock.release_write_lock
        end
      end
      @pool.shutdown
      @pool.wait_for_termination
      queue.close
      error_queue.close
      error_thr.join
      raise "Failed to execute some step(s)" unless error_steps.empty?
    else
      @dep_graph.step_list.each do |step|
        execute_step(step, dry_run, log) if rebuild_set.include? step
      end
    end
  end

  def execute_step(step, dry_run, log)
    prepare_step(step)
    protocol = step.option_dict['protocol']
    protocol ||= 'shell'

    line, column = @analyzer.step_line_and_column step
    proto = DakeProtocol::ProtocolDict[protocol].new(step, @analyzer, @dake_db, dry_run)
    STDERR.puts ("[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] Running #{protocol} step(#{step.object_id}) defined in " +
                 "#{step.src_file} at #{line}:#{column}").colorize(:green)
    STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] step(#{step.object_id}) Script in #{proto.script_file}".colorize(:green) unless dry_run
    step.targets.each do |target|
      next if target.scheme.is_a? DakeScheme::Regex
      if target.scheme.is_a? DakeScheme::Tag
        STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] step(#{step.object_id}) Producing ".colorize(:green) +
                     "@#{target.scheme.path}".colorize(:light_blue)
      else
        STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] step(#{step.object_id}) Producing ".colorize(:green) +
                    "#{target.scheme.path}".colorize(:light_white)
      end
    end
    STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] step(#{step.object_id}) STDOUT in #{proto.script_stdout}".colorize(:green) if log and not dry_run
    STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] step(#{step.object_id}) STDERR in #{proto.script_stderr}".colorize(:green) if log and not dry_run

    if dry_run
      puts step.cmd_text
    else
      proto.execute_step(log)
    end

    STDERR.puts ("[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] Complete #{protocol} step(#{step.object_id}) defined in " +
        "#{step.src_file} at #{line}:#{column}").colorize(:green)
  end

  def prepare_step(step)
    context = step.context.merge!({'OUTPUTN' => 0, 'OUTPUTS' => [], 'INPUTN' => 0, 'INPUTS' => []})
    step.targets.reject { |f| [DakeScheme::Tag, DakeScheme::Regex].include? f.scheme.class }.each_with_index do |output, n|
      name = output.scheme.path
      context["OUTPUT"] = name if n == 0
      context["OUTPUT#{n}"] = name
      context["OUTPUTS"] << name
      context["OUTPUTN"] += 1
    end
    context['OUTPUTN'] = context['OUTPUTN'].to_s
    context['OUTPUTS'] = context['OUTPUTS'].join(" ")
    step.prerequisites.reject { |s| s.tag }.each_with_index do |input, n|
      name = input.scheme.path
      context["INPUT"] = name if n == 0
      context["INPUT#{n}"] = name
      context["INPUTS"] << name
      context["INPUTN"] += 1
    end
    context['INPUTN'] = context['INPUTN'].to_s
    context['INPUTS'] = context['INPUTS'].join(" ")
    @analyzer.analyze_option(step)
    step.cmd_text = prepare_command(step)
  end

  # command preparation is intentionally deferred to execution phase to
  # accelerate the analysis phase of big workflow file
  def prepare_command(step, context={})
    mixin_method = (step.option_dict['method'] ? step.option_dict['method'] : nil)
    method_mode = (step.option_dict['method_mode'] ? step.option_dict['method_mode'] : 'prepend')
    if mixin_method
      meth = @analyzer.method_dict[mixin_method]
      unless meth
        line, column = @analyzer.option_line_and_column(step.options, 'method')
        raise "Method `#{mixin_method}' used in #{step.src_file} at #{line}:#{column} is not defined."
      end
      @analyzer.analyze_option(meth)
      unless step.option_dict['protocol'] == meth.option_dict['protocol']
        line, column = @analyzer.option_line_and_column(step.options, 'protocol')
        line, column = @analyzer.step_line_and_column(step) unless line
        meth_line, meth_column = meth.name.line_and_column
        raise "Method `#{mixin_method}' defined in #{meth.src_file} at #{meth_line}:#{meth_column} " +
              "uses protocol `#{meth.option_dict['protocol']}', which is incompatible with protocol " +
              "`#{step.option_dict['protocol']}' used in #{step.src_file} at #{line}:#{column}."
      end
      if method_mode == 'replace'
        return prepare_command(meth, step.context)
      else
        method_text = prepare_command(meth, step.context)
      end
    end
    cmd_text = ''
    cmd_text << method_text if mixin_method and method_mode == 'prepend'
    first_indent = step.commands[0].items[0].to_s unless step.commands.empty?
    step.commands.each do |command|
      indent = command.items[0]
      if not indent.to_s.start_with? first_indent
        line, column = indent.line_and_column
        raise "Incompatible indentation in #{step.src_file} at #{line}:#{column}."
      else
        indentation = indent.to_s[first_indent.length..-1]
        cmd_text << indentation + @analyzer.text_eval(command, step.src_file, step.context.merge(context), 1) + "\n"
      end
    end
    cmd_text << method_text if mixin_method and method_mode == 'append'
    if cmd_text == ''
      line, column = @analyzer.step_line_and_column step
      step_meth = step.is_a?(StepMethod) ? 'Method' : 'Step'
      raise "#{step_meth} defined in #{step.src_file} at #{line}:#{column} has no commands."
    end
    cmd_text
  end
end
