require 'set'
require 'open3'

# the data struct needed by the executor
# note that this is not nessesarily the complete graph,
# the graph is only used to produce the given targets
DepGraph = Struct.new(
  :succ_step,    # a dict maps each step in the DepGraph to the steps depend on it
  :dep_step,     # a dict maps each step in the DepGraph to the steps it depends on
  :step_list,    # a list of steps represents one sequential execution order
  :root_step,    # a set of steps that hos no dependant
  :leaf_step,    # a set of steps that has no prerequisite
  :need_rebuild  # a set of steps in step_list which should be executed to update their targets
)

class DakeAnalyzer
  attr_reader :workflow, :variable_dict, :method_dict, :included_files
  attr_reader :tag_target_dict, :file_target_dict
  attr_reader :tag_template_dict, :file_template_dict, :step_template_dict

  def initialize(workflow, inclusion_stack, env={})
    @workflow = workflow
    @inclusion_stack = inclusion_stack
    @included_files = inclusion_stack.to_set
    @variable_dict = env.dup
    @method_dict = {}
    @tag_target_dict = {}
    @file_target_dict = {}
    @tag_template_dict = {}
    @file_template_dict = {}
    @step_template_dict = {}
  end

  def analyze_option(step) # method is the same as step
    step.option_dict = {}
    step.options.each do |option|
      name = option.name.to_s
      if option.value.is_a? Parslet::Slice
        value = option.value.to_s
        value = 'true' if value == '+'
        value = 'false' if value == '-'
      else
        value = text_eval(option.value, step.src_file, step.context)
      end
      if step.option_dict[name]
        line, column = option.name.line_and_column
        raise "Option `#{name}' in #{step.src_file} at #{line}:#{column} has already been set."
      else
        if name == 'protocol' and not DakeProtocol::ProtocolDict.keys.include? value
          line, column = option.value.line_and_column
          raise "Protocol `#{value}' in #{step.src_file} at #{line}:#{column} is not supported."
        end
        # TODO: should have more option check
        step.option_dict[name] = value
      end
    end
    step.option_dict['protocol'] = 'shell' unless step.option_dict['protocol']
  end

  def analyze_method(meth)
    if @method_dict[meth.name.to_s]
      line, column = @method_dict[meth.name.to_s].name.line_and_column
      raise "Method `#{meth.name.to_s}' has already beed defined in " +
            "#{@method_dict[meth.name.to_s].src_file} at #{line}:#{column}"
    end
    meth.context = @variable_dict.dup
    analyze_option(meth)
    @method_dict[meth.name.to_s] = meth
  end

  def analyze_scheme(name, step, line, column)
    scheme_part, path_part = name.match(/(\w+:)?(.*)/).to_a[1, 2]
    scheme_cls = DakeScheme::SchemeDict[scheme_part ? scheme_part : 'local:']
    if step
      raise "Scheme `#{scheme_part}' in #{step.src_file} at #{line}:#{column} is not supported." unless scheme_cls
      scheme_cls.new(scheme_part, path_part, step)
    else # for user input target name
      raise "Scheme `#{scheme_part}' in #{name} is not supported." unless scheme_cls
      dummy_step = Step.new([], [], [], {}, nil, nil, @variable_dict, nil, nil)
      scheme_cls.new(scheme_part, path_part, dummy_step)
    end
  end

  def analyze_file(file, type, step)
    line, column = text_line_and_column(file.name)
    if file.flag == '?' and type == :targets
      file_name = text_eval(file.name)
      raise "Output file `#{file_name}' in #{step.src_file} at #{line}:#{column} should not be optional."
    end
    if file.tag
      tag_name = text_eval(file.name, step.src_file, step.context)
      if file.regex
        if type == :prerequisites
          raise "Pattern `#{file_name}' in #{step.src_file} at #{line}:#{column} cannot be used in input file list."
        end
        file.scheme = DakeScheme::Regex.new('^', tag_name, step)
        if type == :targets
          @tag_template_dict[file.scheme.path] ||= []
          @tag_template_dict[file.scheme.path] << step
        end
      else
        file.scheme = DakeScheme::Tag.new('@', tag_name, step)
        if type == :targets
          @tag_target_dict[file.scheme.path] ||= []
          @tag_target_dict[file.scheme.path] << step
        end
      end
      return [file]
    else
      # there maybe more than one file if a file list is generated in command substitution
      file_names = text_eval(file.name, step.src_file, step.context).split("\n")
      files = file_names.map do |file_name|
        if file.regex
          scheme = DakeScheme::Regex.new('^', file_name, step)
        else
          scheme = analyze_scheme(file_name, step, line, column)
        end
        if file_names.length == 1
          file_path = scheme.path
          if type == :targets
            if file.regex
              if @file_template_dict[file_path]
                raise "Output pattern `#{file_name}' in #{step.src_file} at #{line}:#{column} appears in more than one step."
              else
                @file_template_dict[file_path] = step
              end
            else
              if @file_target_dict[file_path]
                raise "Output file `#{file_name}' in #{step.src_file} at #{line}:#{column} appears in more than one step."
              else
                @file_target_dict[file_path] = step
              end
            end
          else
            if file.regex
              raise "Pattern `#{file_name}' in #{step.src_file} at #{line}:#{column} cannot be used in input file list."
            end
          end
        else
          # Generated file list should not be used in targets
          # if type == :targets
          #   raise "File list `#{file_name}' in #{step.src_file} at #{line}:#{column} cannot be used as targets."
          # end
        end
        newfile = file.dup
        newfile.scheme = scheme
        newfile
      end
      return files
    end
  end

  def analyze_step(step)
    step.context = @variable_dict.dup
    # the analysis of prerequisites is deferred to the resolve phase
    step.targets.map! { |file| analyze_file(file, :targets, step) }.flatten!
  end

  def analyze_condition(condition)
    case condition.cond
    when EqCond
      lhs = text_eval condition.cond.eq_lhs
      rhs = text_eval condition.cond.eq_rhs
      if condition.not
        truth = lhs != rhs
      else
        truth = lhs == rhs
      end
    when DefCond
      var_name = condition.cond.var_name.to_s
      if condition.not
        truth = (not @variable_dict.has_key? var_name)
      else
        truth = @variable_dict.has_key? var_name
      end
    end
    truth ? condition.if_body : condition.else_body
  end

  def analyze
    @workflow.tasks.each do |task|
      case task
      when VariableDef
        var_name = task.var_name.to_s
        var_value = text_eval(task.var_value)
        if task.type == :assign
          @variable_dict[var_name] = var_value
        elsif not @variable_dict[var_name]
          @variable_dict[var_name] = var_value
        end
      when Step
        analyze_step(task)
      when StepMethod
        analyze_method(task)
      when Workflow, Inclusion, Condition
        case task
        when Inclusion
          file_names = text_eval(task.files).split("\n")
          file_names.each do |file_name|
            src_dirname = File.dirname(@inclusion_stack[-1])
            path = file_name.start_with?('/') ? file_name : File.absolute_path(file_name, src_dirname)
            if @included_files.include? path
              line, column = text_line_and_column task.files
              raise "Cyclical inclusion detected in #{task.src_file} at #{line}:#{column}"
            else
              @inclusion_stack.push path
            end
            begin
              tree = DakeParser.new.parse(File.read(path))
            rescue Parslet::ParseFailed => failure
              line, column = text_line_and_column task.files
              STDERR.puts "Failed parsing #{path} included from #{task.src_file} at #{line}:#{column}"
              raise failure.message
            end
            workflow = DakeTransform.new.apply(tree, src_file: path)
            if task.type == :include or task.type == :call
              sub_workflow = DakeAnalyzer.new(workflow, @inclusion_stack, @variable_dict).analyze
            else
              sub_workflow = DakeAnalyzer.new(workflow, @inclusion_stack, 'BASE' => File.dirname(path)).analyze
            end
            @inclusion_stack.pop
          end
        when Condition
          body = analyze_condition(task)
          next unless body
          sub_workflow = DakeAnalyzer.new(body, @inclusion_stack, @variable_dict).analyze
        when Workflow # for scope
          sub_workflow = DakeAnalyzer.new(task, @inclusion_stack, @variable_dict).analyze
        end
        @tag_target_dict.merge! sub_workflow.tag_target_dict do |tag, step_list1, step_list2|
          step_list1 + step_list2
        end
        @file_target_dict.merge! sub_workflow.file_target_dict do |file, step1, step2|
            file1 = step1.targets.find { |target| target.scheme.path == file }
            file2 = step2.targets.find { |target| target.scheme.path == file }
            line1, column1 = text_line_and_column file1.name
            line2, column2 = text_line_and_column file2.name
            file2_name = file2.scheme.path
            raise "Output file `#{file2_name}' defined in #{step2.src_file} at #{line2}:#{column2} " +
                  "was previously defined in #{step1.src_file} at #{line1}:#{column1}."
          end
        @file_template_dict.merge! sub_workflow.file_template_dict do |file, (scheme1, step1), (scheme2, step2)|
          file1 = step1.targets.find { |target| target.scheme.path == file }
          file2 = step2.targets.find { |target| target.scheme.path == file }
          line1, column1 = text_line_and_column file1.name
          line2, column2 = text_line_and_column file2.name
          file2_name = file2.scheme.path
          raise "Output pattern `#{file2_name}' defined in #{step2.src_file} at #{line2}:#{column2} " +
                    "was previously defined in #{step1.src_file} at #{line1}:#{column1}."
        end
        if task.is_a? Condition or (task.is_a? Inclusion and task.type == :include)
          @variable_dict.merge! sub_workflow.variable_dict
        end
      end
    end
    self
  end

  def step_line_and_column(step)
    return step.name.line_and_column if step.is_a? StepMethod
    first_target = step.targets[0]
    if first_target.name.is_a? Parslet::Slice
    	first_target.name.line_and_column
    else
	    text_line_and_column(first_target.name)
	  end
  end

  def option_line_and_column(options, option_name)
    options.each do |option|
      next unless option.name.to_s == option_name
      if option.value.is_a? Parslet::Slice
        return option.value.line_and_column
      else
        return text_line_and_column option.value
      end
    end
    nil
  end

  def text_line_and_column(text)
    first_item = text.items[0]
    case first_item
    when Chars then first_item.string.line_and_column
    when VariableSub
      line, column = first_item.var_name.line_and_column
      [line, column - 2]
    when CommandSub
      line, column = text_line_and_column first_item.cmd_text
      [line, column - 2]
    end
  end

  def print_target(target, tag, target_step, dep_graph = nil, pad_stack = [])
    pad_prefix = ''
    unless pad_stack.empty?
      pad_prefix += pad_stack.reduce('') do |str, pad|
        next str + '│   ' if pad == '├'
        next str + '    ' if pad == '└'
      end
    end
    pwd = Pathname.new(Dir.pwd)
    target_path = if tag then '@' + target
                  elsif target.start_with? '/'
                    Pathname.new(target).relative_path_from(pwd)
                  else
                    target
                  end
    if target_step
      workflow_path = Pathname.new(target_step.src_file).relative_path_from(pwd)
      line, column = step_line_and_column(target_step)

      pad = (pad_stack.empty? ? '' : pad_prefix[0...-4] + pad_stack.last + '── ')
      puts pad.colorize(:magenta) +
           "#{target_path}".colorize((tag ? :light_blue : :light_white)) +
           " in " +
           "#{workflow_path} ".colorize(:green) +
           "#{line}:#{column} ".colorize(:yellow)
      unless target_step.doc_str.empty?
        pad = (pad_stack.empty? ? '│ ' : pad_prefix + '│ ')
        target_step.doc_str.each do |doc|
          if target_step.prerequisites.empty? or not dep_graph
            puts (pad[0...-2] + (doc == target_step.doc_str.last ? '\_' : '│ ') + doc.string.to_s).colorize(:magenta)
          else
            puts (pad + doc.string.to_s).colorize(:magenta)
          end
        end
      end
    else
      pad = (pad_stack.empty? ? '' : pad_prefix[0...-4] + pad_stack.last + '── ')
      puts pad.colorize(:magenta) +
           "#{target_path}".colorize((tag ? :light_blue : :light_white)) +
           " (No step) "
    end

    if target_step and dep_graph
      dep_steps = dep_graph.dep_step[target_step]
      pairs = target_step.prerequisites.each_with_object([]) do |prereq, pairs|
        steps = dep_steps.find_all { |dep_step| dep_step.targets.any? { |tar| tar.scheme.path == prereq.scheme.path } }
        if steps.empty?
          pairs << [prereq, nil]
        else
          steps.each { |step| pairs << [prereq, step]}
        end
      end
      while pair = pairs.pop
        pad_stack << (pairs.empty? ? '└' : '├')
        prerequisite, step = pair
        print_target(prerequisite.scheme.path, prerequisite.tag, step, dep_graph, pad_stack)
        pad_stack.pop
      end
    end
  end

  # src_file is needed by prepare_command in execution phase
  # because @inclusion_stack will have only root workflow by then
  def text_eval(text, src_file=@inclusion_stack[-1], context=@variable_dict, skip=0)
    text.items[skip..-1].reduce('') do |string, item|
      case item
      when Chars
        string.concat item.string.to_s
      when VariableSub
        var_name = item.var_name.to_s
        var_value = context[var_name]
        if var_value
          string.concat var_value
        else
          line, column = item.var_name.line_and_column
          raise "Variable `#{var_name}' in #{src_file} at #{line}:#{column} is not defined."
        end
      when CommandSub
        command = text_eval(item.cmd_text, src_file, context)
        stdout, stderr, status = Open3.capture3(command, :chdir=>@variable_dict['BASE'])
        if status.success?
          string.concat stdout.chomp
        else
          line, column = text_line_and_column item.cmd_text
          raise "Command `#{command}' in #{src_file} at #{line}:#{column} failed " +
                 "with EXIT_STATUS:#{status.exitstatus} and STDERR:\n#{stderr}"
        end
      else # For Escaped Char
        string.concat item.to_s
      end
      string
    end
  end
end
