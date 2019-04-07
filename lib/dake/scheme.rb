module DakeScheme
  class Scheme
    PATTERN = ['']
    attr_reader :path, :step, :src
    def initialize(scheme_part, path_part, step)
      @src = scheme_part + path_part
      @path = path_part
      @step = step
    end
    def checksum; end
    def mtime; end
    def exist?; false end
  end

  class Tag < Scheme
    PATTERN = ['@']
    def initialize(scheme_part, path_part, step)
      @src = scheme_part + path_part
      @path = path_part
      @step = step
      @step = step
    end
  end

  class Regex < Scheme
    PATTERN = ['^']
    def initialize(scheme_part, path_part, step)
      @src = path_part
      @path = Regexp.compile("^#{path_part}$")
      @step = step
    end
  end

  class Local < Scheme
    PATTERN = ['local:']
    def initialize(scheme_part, path_part, step)
      if path_part.start_with? '/'
       @path = path_part
       @src = Pathname.new(path_part).relative_path_from(step.context['BASE'])
      else
        @path = File.expand_path(path_part, step.context['BASE'])
        @src = path_part
      end
      @step = step
    end

    def mtime
      File.mtime(@path)
    end

    def exist?
      File.exist?(@path)
    end
  end

  class HDFS < Scheme
    PATTERN = ['hdfs:', 'afs:']
    def initialize(scheme_part, path_part, step)
      @src = scheme_part + path_part
      @path = scheme_part + path_part
      @step = step
      if @step.context['HADOOP_HOME']
        @hadoop_bin = "#{@step.context['HADOOP_HOME']}/hadoop/bin/hadoop"
      elsif ENV['HADOOP_HOME']
        @hadoop_bin = "#{ENV['HADOOP_HOME']}/hadoop/bin/hadoop"
      else
        raise "HADOOP_HOME not set." if not hadoop_home or hadoop_home.empty?
      end
      raise "#{@hadoop_bin} not found." unless File.exist? @hadoop_bin
    end

    def mtime
      Time.at(`#{@hadoop_bin} fs -stat %Y #{@path}`.chomp.to_i / 1000)
    end

    def exist?
      system("#{@hadoop_bin} fs -test -e #{@path}")
    end
  end

  SchemeDict = {
      'local:' => Local,
      'hdfs:'  => HDFS,
      'afs:'   => HDFS
  }
end
