SRC_DIR = "/var/opt/git_shell"
require 'yaml'
require 'pathname'
require 'fileutils'

module GitLib
  
  begin
    # Try to require the preresolved locked set of gems.
    env_path = "#{SRC_DIR}/.bundle/environment"
    require env_path
  rescue LoadError
    # Fall back on doing an unlocked resolve at runtime.
    require "rubygems"
    require "bundler"
    env_path
    gemfile_path = "#{SRC_DIR}"
    ENV['BUNDLE_GEMFILE'] ||= File.join(gemfile_path, 'Gemfile')
    Bundler.setup
  end
  require "rails_config"
  require "brawne"
  
  # loading up the config
  RailsConfig.setup { |config| config.const_name = "Settings" }
  RailsConfig.load_and_set_settings(File.expand_path("#{SRC_DIR}/config/settings.yml"), File.expand_path("#{SRC_DIR}/config/settings/production.yml"))

  class SimpleLogger
    def initialize(file)
      @log_file = file
    end
  
    def info(msg)
      write("info",msg)
    end
    def warn(msg)
      write("warn",msg)
    end
    def error(msg)
      write("error",msg)
    end
    def write(level, msg)
      File.open(@log_file, "a") { |f| f.puts "#{level[0].capitalize} :: #{Time.now.to_s} : #{msg}"}
    end
  end

    
  class Command
   # loading up the config
  RailsConfig.setup { |config| config.const_name = "Settings" }
  RailsConfig.load_and_set_settings(File.expand_path("#{SRC_DIR}/config/settings.yml"), File.expand_path("#{SRC_DIR}/config/settings/production.yml"))
    attr_accessor :cmd_type, :cmd_cmd, :cmd_opt, :fake_path, :real_path, :git_user, :user_login,
     :user_email, :user_id, :read, :write, :kind, :fresh_cmd, :brawne
    attr_accessor :logger

    def self.check_rights(username, repository_name)
      result = Brawne::Request.get("/api/git/rights?username=#{username}&repository=#{repository_name}")
      return JSON.parse(result[1])["access"] if result[0].to_i == 200
      return false
    end
     
    def is_write?
      return write
    end

    def is_read?
      return read
    end

    def is_git?
      return true if self.kind == "git"
      return false
    end

    def initialize(user,command)
      # r or w (read or write)
      @cmd_type = ""
      # the git command
      @cmd_cmd = ""
      # the options
      @cmd_opt = ""
      # fake path
      @fake_path = ""
      # real path
      @real_path = ""
      # user login
      @user = user
      @kind = nil
      @fresh_cmd = command
      Brawne.setup do |config| 
        config.host = Settings.egg_api.host
        config.port = Settings.egg_api.port
        config.ssl = Settings.egg_api.ssl
        config.user = Settings.egg_api.username
        config.token = Settings.egg_api.token
      end
      @logger = SimpleLogger.new(SRC_DIR + "/logs/general.log")
    end

    def repo(command)
    end

    # basic sanity check and split of the command line
    def check(command)
      self.kind = "git" # that's for sure
      reads = ["git-upload-pack", "git upload-pack"]
      writes = ["git-receive-pack", "git receive-pack"]
      sh_command = command.split(" ")
      if sh_command.size == 3
        self.cmd_cmd = sh_command[0] + " " + sh_command[1]
        self.cmd_opt = sh_command[2]
      elsif sh_command.size == 2
        self.cmd_cmd = sh_command[0]
        self.cmd_opt = sh_command[1]
      else
        return false
      end

      # check the command for type, not really used but hey, always good to have
      if reads.include?(self.cmd_cmd)
        self.read = true
        logger.info("Read command")
      end
      if writes.include?(self.cmd_cmd)
        self.write = true
        logger.info("Write command")
      end
      return true
    end

    # create the proper repository path on the system
    def repo_path
      if !self.cmd_opt.empty?
        self.fake_path = repo_name
        # real path is something like /jupiler_home/repositories/username/repo_name
        self.real_path = Settings.jup_sh.home + '/' +
                self.username_from_cmd + "/" +
                self.fake_path
        return self.real_path
      end
    end

    # extract the repo name from the command
    def repo_name
      # the repo is the last part of the path
      return self.cmd_opt.gsub("'","").split("/")[-1] if !self.cmd_opt.empty?
    end

    # extract the user name from the command
    def username_from_cmd
      # the username is the first part of the path
      return self.cmd_opt.gsub("'","").split("/")[0] if !self.cmd_opt.empty?
    end

    # the exec of the command
    def run
      logger.info("Running command : git-shell -c #{@cmd_cmd} '#{@real_path}'")
      if system(Settings.git.shell, "-c", "#{@cmd_cmd} '#{@real_path}'")
        logger.info("\t\tOK")
      else
        logger.info("\t\tKO")
      end
    end

    def self.kickstart!(user, sh_command)
      begin
        key = nil
        command = self.new(user, sh_command)
        command.logger.info("kick start")
        if command.check(sh_command)
          # extracting precious info from command
          username = command.username_from_cmd
          repo_path = command.repo_path
          repo_name = command.repo_name
          
          # we need to know if user as access to the requested repository
          # username is guessed from the command, the ssh key as already been accepted
          # repository name is guessed from the command too, it gives Egg name
          # expected : true or false
          command.logger.info("cheking rights")
          has_right = Command.check_rights(username, repo_name)
  
          if has_right
            # ok user is allowed to run the command (we don't check for read or write)
            command.logger.info("#{command.user_login} can use #{repo_name}")
            command.run
          else
            # user has not right to pass
            command.logger.info("insufficiant rights for #{command.user_login}")
          end
        else
          command.logger.info("Command Invalid !")
        end
      rescue => e
	STDERR.puts e.to_s
      end
    end
  end
end
