module DakeProtocol
  class Protocol
    EXT_NAME = ''
    attr_reader :exec_path, :script_stdout, :script_stderr
    def initialize(step, analyzer, dake_db, dry_run)
      @step = step
      @analyzer = analyzer
      @dake_db = dake_db
      date = DAKE_EXEC_TIME.strftime('%Y%m%d')
      time = DAKE_EXEC_TIME.strftime('%H_%M_%S')
      @exec_path = "#{@dake_db.database_path}/#{date}/#{time}_#{DAKE_EXEC_PID}"
      @script_stdout = "#{@exec_path}/step.#{@step.object_id}.out"
      @script_stderr = "#{@exec_path}/step.#{@step.object_id}.err"
      FileUtils.mkdir_p(@exec_path) if not dry_run and not File.exist? @exec_path
    end

    def script_file
      "#{@exec_path}/step.#{@step.object_id}.#{self.class::EXT_NAME}"
    end

    def create_script
      file = File.open(script_file, 'w')
      file.write @step.cmd_text
      file.close
      file
    end

    def execute_step(log=false)
    end
  end

  class Shell < Protocol
    EXT_NAME = 'sh'
    def execute_step(log=false)
      file = create_script
      if log
        ret = system(@step.context, "sh #{file.path} " +
                     "2> #{@script_stderr} 1> #{@script_stdout}", :chdir=>@step.context['BASE'])
      else
        ret = system(@step.context, "sh #{file.path}", :chdir=>@step.context['BASE'])
      end
      unless ret
        line, column = @analyzer.step_line_and_column @step
        raise "Step(#{@step.object_id}) defined in #{@step.src_file} at #{line}:#{column} failed."
      end
    end
  end

  class AWK < Protocol
    EXT_NAME = 'awk'
    def execute_step(log=false)
      if @step.targets.size != 1 or (!@step.targets[0].tag and not @step.targets[0].scheme.is_a? DakeScheme::Local)
        raise "awk step should have only one local output file or tag."
      end
      inputs = @step.prerequisites.reject { |target| target.tag }
      infile = inputs.map do |input|
        raise "awk step should have only local input files." unless input.scheme.is_a? DakeScheme::Local
        input.scheme.path
      end.join(' ')
      file = create_script
      if @step.targets[0].tag
        if log
          ret = system(@step.context, "awk -f #{file.path} #{infile} " +
                       "2> #{@script_stderr} 1> #{@script_stdout}", :chdir=>@step.context['BASE'])
        else
          ret = system(@step.context, "awk -f #{file.path} #{infile}", :chdir=>@step.context['BASE'])
        end
      else
        if log
          ret = system(@step.context, "awk -f #{file.path} #{infile} " +
                       "2> #{@script_stderr} 1> #{@step.targets[0].path}", :chdir=>@step.context['BASE'])
        else
          ret = system(@step.context, "awk -f #{file.path} #{infile}", :chdir=>@step.context['BASE'])
        end
      end
      unless ret
        line, column = @analyzer.step_line_and_column @step
        raise "Step(#{@step.object_id}) defined in #{@step.src_file} at #{line}:#{column} failed."
      end
    end
  end

  class Python < Protocol
    EXT_NAME = 'py'
    def execute_step(log=false)
      file = create_script
      if log
        ret = system(@step.context, "python #{file.path} " +
                     "2> #{@script_stderr} 1> #{@script_stdout}", :chdir=>@step.context['BASE'])
      else
        ret = system(@step.context, "python #{file.path}", :chdir=>@step.context['BASE'])
      end
      unless ret
        line, column = @analyzer.step_line_and_column @step
        raise "Step(#{@step.object_id}) defined in #{@step.src_file} at #{line}:#{column} failed."
      end
    end
  end

  class Ruby < Protocol
    EXT_NAME = 'rb'
    def execute_step(log=false)
      file = create_script
      if log
        ret = system(@step.context, "ruby #{file.path} " +
                     "2> #{@script_stderr} 1> #{@script_stdout}", :chdir=>@step.context['BASE'])
      else
        ret = system(@step.context, "ruby #{file.path}", :chdir=>@step.context['BASE'])
      end
      unless ret
        line, column = @analyzer.step_line_and_column @step
        raise "Step(#{@step.object_id}) defined in #{@step.src_file} at #{line}:#{column} failed."
      end
    end
  end

  class Rscript < Protocol
    EXT_NAME = 'R'
    def execute_step(log=false)
      file = create_script
      if log
        ret = system(@step.context, "Rscript --slave --vanilla #{file.path} " +
                     "2> #{@script_stderr} 1> #{@script_stdout}", :chdir=>@step.context['BASE'])
      else
        ret = system(@step.context, "Rscript --slave --vanilla #{file.path}", :chdir=>@step.context['BASE'])
      end
      unless ret
        line, column = @analyzer.step_line_and_column @step
        raise "Step(#{@step.object_id}) defined in #{@step.src_file} at #{line}:#{column} failed."
      end
    end
  end

  ProtocolDict = {
      'shell'  => Shell,
      'python' => Python,
      'ruby'   => Ruby,
      'r'      => Rscript,
      'awk'    => AWK
  }
end
