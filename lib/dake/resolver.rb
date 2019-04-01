class DakeResolver
  def initialize(analyzer)
    @analyzer = analyzer
  end

  # check if a step needs to be executed to produce the given targets
  def need_execute?(targets, step)
    max_mtime = nil
    targets.each do |target|
      # a tag target can be thought as newer than any prerequisite,
      # the step should always be executed to produce the tag target
      return true if target.tag

      # if a target doesn't exist, the step should always be executed to produce it
      return true unless target.scheme.exist?
      target_mtime = target.scheme.mtime

      # find the newest modification time in all targets
      if max_mtime
        max_mtime = target_mtime if target_mtime > max_mtime
      else
        max_mtime = target_mtime
      end
    end

    files = step.prerequisites.reject { |dep| dep.tag }
    files.each do |file|
      next if file.flag == '?'
      # if any required file is newer than the newest target,
      # the step should be executed to update the target
      if file.scheme.exist?
        file_mtime = file.scheme.mtime
        return true if file_mtime > max_mtime
      else
        # if a required file doesn't exist,
        # it means a step should be executed to produce the file,
        # and the newly produced file will be newer than all the targets,
        # therefore this step should also be executed
        return true
      end
    end
    # if not in any case above, the step doesn't need to be executed
    false
  end

  def find_steps(target_scheme, tag, optional=false)
    target_name = target_scheme.path
    target_src = target_scheme.src
    if tag
      steps = @analyzer.tag_target_dict[target_name]
      if not steps
        mdata = nil
        _, template_steps = @analyzer.tag_template_dict.detect do |regex, _|
          mdata = regex.match target_name
        end
        if template_steps
          @analyzer.tag_target_dict[target_name] ||= []
          steps = []
          template_steps.each do |template_step|
            if @analyzer.step_template_dict[template_step] and
               @analyzer.step_template_dict[template_step][mdata.named_captures]
              step = @analyzer.step_template_dict[template_step][mdata.named_captures]
            else
              step = template_step.dup
              step.targets = template_step.targets.dup
              step.prerequisites = template_step.prerequisites.dup
              step.context = template_step.context.dup
              step.context.merge! mdata.named_captures
              @analyzer.step_template_dict[template_step] ||= {}
              @analyzer.step_template_dict[template_step][mdata.named_captures] = step
            end
            step.targets.map! do |file|
              if file.scheme.is_a? DakeScheme::Regex and file.scheme.path.match target_name
                new_file = file.dup
                new_file.scheme = DakeScheme::Tag.new('@', target_name, step)
                new_file
              else
                file
              end
            end
            @analyzer.tag_target_dict[target_name] << step
            steps << step
          end
        else
          raise "No step found for building tag `#{target_name}'."
        end
      end
    else
      step = @analyzer.file_target_dict[target_name]
      if step
        steps = [step]
      else
        mdata = nil
        _, template_step = @analyzer.file_template_dict.detect do |regex, _|
          mdata = regex.match target_src
        end
        if template_step
          if @analyzer.step_template_dict[template_step] and
             @analyzer.step_template_dict[template_step][mdata.named_captures]
            step = @step_template_dict[template_step][mdata.named_captures]
          else
            step = template_step.dup
            step.targets = template_step.targets.dup
            step.prerequisites = template_step.prerequisites.dup
            step.context = template_step.context.dup
            step.context.merge! mdata.named_captures
            @analyzer.step_template_dict[template_step] ||= {}
            @analyzer.step_template_dict[template_step][mdata.named_captures] = step
          end
          step.targets.map! do |file|
            if file.scheme.is_a? DakeScheme::Regex and file.scheme.path.match target_src
              line, column = @analyzer.text_line_and_column(file.name)
              new_file = file.dup
              new_file.scheme = @analyzer.analyze_scheme(target_name, step, line, column)
              new_file
            else
              file
            end
          end
          @analyzer.file_target_dict[target_name] = step
          steps = [step]
        else
          scheme = @analyzer.analyze_scheme(target_name, nil, nil, nil)
          if optional or scheme.exist?
            steps = []
          else
            raise "No step found for building file `#{target_name}'."
          end
        end
      end
    end
    steps
  end

  # resolve the dependency graph and generate step list for sequential execution
  def resolve(target_dict, no_check=false)
    step_list = []
    visited = Set.new
    path_visited = Set.new
    leaf_steps = Set.new
    target_steps = Set.new
    need_rebuild = Set.new
    succ_step_dict = {}
    dep_step_dict = {}
    dep_step_list = {}
    succ_target_dict = {}

    target_dict.each do |target_name, target_opts|
      if target_opts.tag
        dummy_step = Step.new([], [], [], {}, nil, nil, @analyzer.variable_dict, nil, nil)
        scheme = DakeScheme::Tag.new('@', target_name, dummy_step)
      else
        scheme = @analyzer.analyze_scheme(target_name, nil, nil, nil)
      end
      dep_steps = find_steps(scheme, target_opts.tag, no_check)
      dep_steps.each do |dep_step|
        target = dep_step.targets.find { |target| target.scheme.path == scheme.path }
        succ_target_dict[dep_step] ||= Set.new
        succ_target_dict[dep_step] << target
        target_steps << dep_step
        succ_step_dict[dep_step] ||= Set.new
      end
    end

    target_steps.each do |target_step|
      stack = []
      stack.push target_step unless visited.include? target_step
      until stack.empty?
        step = stack.last
        visited << step
        path_visited << step
        unless dep_step_dict[step]
          dep_step_dict[step] = Set.new
          step.prerequisites.map! { |file| @analyzer.analyze_file(file, :prerequisites, step) }.flatten!
          step.prerequisites.each do |dep|
            dep_steps = find_steps(dep.scheme, dep.tag, (dep.flag == '?' or no_check))
            dep_steps.each do |dep_step|
              dep_step_dict[step] << dep_step
              succ_step_dict[dep_step] ||= Set.new
              succ_step_dict[dep_step] << step
              succ_target_dict[dep_step] ||= Set.new
              succ_target_dict[dep_step] << dep
              if path_visited.include? dep_step
                ofile = dep_step.targets.find { |prev_target| prev_target.scheme.path == dep.scheme.path }
                ln1, col1 = ofile.tag ? ofile.name.line_and_column : @analyzer.text_line_and_column(ofile.name)
                ln2, col2 = dep.tag ? dep.name.line_and_column : @analyzer.text_line_and_column(dep.name)
                STDERR.puts 'Cyclical dependency detected.'
                raise "Output `#{dep.scheme.path}' defined in #{dep_step.src_file} at #{ln1}:#{col1} " +
                          "is defined as Input in #{step.src_file} at #{ln2}:#{col2}."
              end
            end
          end
          dep_step_list[step] = dep_step_dict[step].to_a
        end
        while next_step = dep_step_list[step].pop
          break unless visited.include? next_step
        end
        if next_step
          stack.push next_step
        else
          stack.pop
          path_visited.delete step
          step_list << step
          leaf_steps << step if dep_step_dict[step].empty?
        end
      end
    end
    step_list.each do |step|
      if leaf_steps.include? step
        need_rebuild << step if no_check or need_execute?(succ_target_dict[step], step)
      else
        if dep_step_dict[step].any? { |dep_step| need_rebuild.include? dep_step }
          need_rebuild << step
        else
          need_rebuild << step if no_check or need_execute?(succ_target_dict[step], step)
        end
      end
    end
    root_steps = target_steps.select { |step| succ_step_dict[step].empty? }.to_set
    DepGraph.new(succ_step_dict, dep_step_dict, step_list, root_steps, leaf_steps, need_rebuild)
  end
end