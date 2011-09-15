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
  
  # loading up the config
  RailsConfig.setup { |config| config.const_name = "Settings" }
  RailsConfig.load_and_set_settings File.expand_path("#{SRC_DIR}/config/settings.yml")
    
  class Command
    attr_accessor :cmd_type, :cmd_cmd, :cmd_opt, :fake_path, :real_path, :git_user, :user_login,
     :user_email, :user_id, :read, :write, :kind, :fresh_cmd, :brawne

    def self.check_rights(username, repository_name)
      result = Brawne::Request.get("/api/git/rights?username=#{username}&repository=#{repository_name}")
      return JSON.parse(result[1])["access"] if result[0].to_i == 200
      return false
    end
     
    def logger(message)
      FileUtils.mkdir(SRC_DIR + "/logs") unless File.exist?(SRC_DIR + "/logs")
      File.open(SRC_DIR + "/logs/general.log", "a") do |log|
        log.puts Time.now.strftime("%d/%m/%y %H:%M ") + message
      end
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
    end

    def repo(command)
    end

    # basic sanity check and split of the command line
    def check(command)
      self.kind = "git" # that's for sure
      self.logger("Git command")
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
        self.logger("Read command")
      end
      if writes.include?(self.cmd_cmd)
        self.write = true
        self.logger("Write command")
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
      self.logger("Running command : git-shell -c #{@cmd_cmd} '#{@real_path}'")
      if system(Settings.git.shell, "-c", "#{@cmd_cmd} '#{@real_path}'")
        self.logger("\t\tOK")
      else
        self.logger("\t\tKO")
      end
    end

    def self.kickstart!(user, sh_command)
      key = nil
      command = self.new(user, sh_command)
      if command.check(sh_command)
        # extracting precious info from command
        username = command.username_from_cmd
        repo_path = command.repo_path
        repo_name = command.repo_name
        
        # we need to know if user as access to the requested repository
        # username is guessed from the command, the ssh key as already been accepted
        # repository name is guessed from the command too, it gives Egg name
        # expected : true or false
        has_right = Command.check_rights(username, repo_name)

        if has_right
          # ok user is allowed to run the command (we don't check for read or write)
          command.logger("#{command.user_login} can use #{repo_name}")
          command.run
        else
          # user has not right to pass
          command.logger("insufficiant rights for #{command.user_login}")
        end
      else
        command.logger("Command Invalid !")
      end
    end
  end
end
