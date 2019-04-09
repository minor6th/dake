# require 'git'
# require "sqlite3"

class DakeDB
  attr_reader :database_path, :database_file
  def initialize(path)
    workflow_path = File.dirname(path)
    @database_path = workflow_path + '/.dake'
    @database_file = database_path + '/step_history.db'

    FileUtils.mkdir(@database_path) unless File.exist? @database_path
    # @db = SQLite3::Database.new database_file
    # @db.execute <<-SQL
    #   create table if not exists step_history (
    #     id int unsigned auto_increment primary key,
    #     step_sha1 binary(20) not null
    #     target varchar(50),
    #     process_id big int(50),
    #     start_time varchar(5),
    #     end_time varchar(5),
    #     ip_address binary(4)
    #   );
    #   create table if not exists step_target (
    #     id int unsigned auto_increment primary key,
    #     target varchar(1024),
    #     type char(50)
    #   );
    # SQL

    # git_opts = {
    #     repository: database_path + '/.git',
    #     index: database_path + '/.git/index',
    #     log: Logger.new(File.open(database_path + '/git.log', 'w+'))
    # }

    # if File.exist? database_path + '/.git'
    #   @git = Git.open(workflow_path, git_opts)
    # else
    #   @git = Git.init(workflow_path, git_opts)
    #   @git.config('user.name', 'Dake User')
    #   @git.config('user.email', 'email@email.com')
    #   File.open(database_path + '/.gitignore', 'w') do |f|
    #     f.puts File.basename('.dake')
    #   end
    #   @git.add(database_path + '/.gitignore')
    #   @git.commit('init commit')
    # end
  end
end
