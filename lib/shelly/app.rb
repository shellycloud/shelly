require 'erb'
require 'launchy'
require 'shelly/backup'

module Shelly
  class App < Model
    DATABASE_KINDS = %w(postgresql mongodb redis)
    DATABASE_CHOICES = DATABASE_KINDS + %w(none)
    SERVER_SIZES = %w(small large)

    attr_accessor :code_name, :databases, :ruby_version, :environment,
      :git_url, :domains, :web_server_ip, :size, :thin, :redeem_code,
      :content, :organization, :zone_name

    def initialize(code_name = nil, content = nil)
      self.code_name = code_name
      self.content = content
    end

    def thin
      size == "small" ? 2 : 4
    end

    def puma
      size == "small" ? 1 : 2
    end

    def databases=(dbs)
      @databases = dbs - ['none']
    end

    def add_git_remote
      system("git remote rm #{code_name} > /dev/null 2>&1")
      system("git remote add #{code_name} #{git_url}")
    end

    def git_remote_exist?
      IO.popen("git remote").read.include?(code_name)
    end

    def git_fetch_remote
      system("git fetch #{code_name} > /dev/null 2>&1")
    end

    def git_add_tracking_branch
      system("git checkout -b #{code_name} --track #{code_name}/master > /dev/null 2>&1")
    end

    def remove_git_remote
      system("git remote rm #{code_name} > /dev/null 2>&1")
    end

    def create
      attributes = {:code_name => code_name,
                    :redeem_code => redeem_code,
                    :organization_name => organization,
                    :zone_name => zone_name}
      response = shelly.create_app(attributes)
      assign_attributes(response)
    end

    def create_cloudfile
      cloudfile = Cloudfile.new
      cloudfile.code_name = code_name
      cloudfile.ruby_version = ruby_version
      cloudfile.environment = environment
      cloudfile.domains = domains
      cloudfile.size = size
      if ruby_version == 'jruby'
        cloudfile.puma = puma
      else
        cloudfile.thin = thin
      end
      cloudfile.databases = databases
      cloudfile.create
    end

    def delete
      shelly.delete_app(code_name)
    end

    def deploy_logs
      shelly.deploy_logs(code_name)
    end

    def deploy_log(log)
      shelly.deploy_log(code_name, log)
    end

    def application_logs(options = {})
      shelly.application_logs(code_name, options)
    end

    def application_logs_tail
      shelly.application_logs_tail(code_name) { |l| yield(l) }
    end

    def database_backups
      shelly.database_backups(code_name).map do |attributes|
        Shelly::Backup.new(attributes.merge("code_name" => code_name))
      end
    end

    def database_backup(handler)
      attributes = shelly.database_backup(code_name, handler)
      Shelly::Backup.new(attributes.merge("code_name" => code_name))
    end

    def restore_backup(filename)
      shelly.restore_backup(code_name, filename)
    end

    def request_backup(kinds)
      Array(kinds).each do |kind|
        shelly.request_backup(code_name, kind)
      end
    end

    def logs
      shelly.cloud_logs(code_name)
    end

    def start
      shelly.start_cloud(code_name)["deployment"]["id"]
    end

    def stop
      shelly.stop_cloud(code_name)["deployment"]["id"]
    end

    # returns the id of created deployment
    def redeploy
      shelly.redeploy(code_name)["deployment"]["id"]
    end

    def deployment(deployment_id)
      shelly.deployment(code_name, deployment_id)
    end

    def self.guess_code_name
      guessed = nil
      cloudfile = Cloudfile.new
      if cloudfile.present?
        clouds = cloudfile.clouds.map(&:code_name)
        if clouds.grep(/staging/).present?
          guessed = "production"
          production_clouds = clouds.grep(/production/)
          production_clouds.sort.each do  |cloud|
            cloud =~ /production(\d*)/
            guessed = "production#{$1.to_i+1}"
          end
        end
      end
      "#{File.basename(Dir.pwd)}-#{guessed || 'staging'}".downcase.dasherize
    end

    def configs
      @configs ||= shelly.app_configs(code_name)
    end

    def user_configs
      configs.find_all { |config| config["created_by_user"] }
    end

    def shelly_generated_configs
      configs.find_all { |config| config["created_by_user"] == false }
    end

    def config(path)
      shelly.app_config(code_name, path)
    end

    def create_config(path, content)
      shelly.app_create_config(code_name, path, content)
    end

    def update_config(path, content)
      shelly.app_update_config(code_name, path, content)
    end

    def delete_config(path)
      shelly.app_delete_config(code_name, path)
    end

    def rake(task)
      ssh(:command => "rake_runner \"#{task}\"")
    end

    def dbconsole
      ssh(:command => "dbconsole")
    end

    def attributes
      @attributes ||= shelly.app(code_name)
    end

    def statistics
      @stats ||= shelly.statistics(code_name)
    end

    def web_server_ip
      attributes["web_server_ip"]
    end

    def git_info
      attributes["git_info"]
    end

    def state
      attributes["state"]
    end

    def credit
      attributes["organization"]["credit"].to_f
    end

    def organization_details_present?
      attributes["organization"]["details_present"]
    end

    def self.inside_git_repository?
      system("git status > /dev/null 2>&1")
    end

    def to_s
      code_name
    end

    def edit_billing_url
      "#{shelly.shellyapp_url}/organizations/#{organization || code_name}/edit"
    end

    def open
      Launchy.open("http://#{attributes["domain"]}")
    end

    def console(server = nil)
      ssh(:server => server)
    end

    def list_files(path)
      ssh(:command => "ls -l /srv/glusterfs/disk/#{path}")
    end

    def upload(source)
      conn = console_connection
      rsync(source, "#{conn['host']}:/srv/glusterfs/disk")
    end

    def download(relative_source, destination)
      conn = console_connection
      source = File.join("#{conn['host']}:/srv/glusterfs/disk", relative_source)
      rsync(source, destination)
    end

    def delete_file(remote_path)
      ssh(:command => "delete_file #{remote_path}")
    end

    # Public: Return databases for given Cloud in Cloudfile
    # Returns Array of databases
    def cloud_databases
      content["servers"].map do |server, settings|
        settings["databases"]
      end.flatten.uniq
    end

    # Public: Delayed job enabled?
    # Returns true if delayed job is present
    def delayed_job?
      option?("delayed_job")
    end

    # Public: Whenever enabled?
    # Returns true if whenever is present
    def whenever?
      option?("whenever")
    end

    # Public: Sidekiq enabled?
    # Returns true if sidekiq is present
    def sidekiq?
      option?("sidekiq")
    end

    # Public: Return databases to backup for given Cloud in Cloudfile
    # Returns Array of databases, except redis db
    def backup_databases
      cloud_databases - ['redis']
    end

    # Public: Return true when app has been deployed
    # false otherwise
    def deployed?
      git_info["deployed_commit_sha"].present?
    end

    # Public: Return list of not deployed commits
    # Returns: A list of commits as a String with new line chars
    # format: "#{short SHA} #{commit message} (#{time, ago notation})"
    def pending_commits
      current_commit = IO.popen("git rev-parse 'HEAD'").read.strip
      format = "%C(yellow)%h%Creset %s %C(red)(%cr)%Creset"
      range = "#{git_info["deployed_commit_sha"]}..#{current_commit}"
      IO.popen(%Q{git log --no-merges --oneline --pretty=format:"#{format}" #{range}}).read.strip
    end

    private

    def assign_attributes(response)
      self.git_url = response["git_url"]
      self.domains = response["domains"]
      self.ruby_version = jruby? ? 'jruby' : response["ruby_version"]
      self.environment = response["environment"]
    end

    def jruby?
      RUBY_PLATFORM == 'java'
    end

    # Internal: Checks if specified option is present in Cloudfile
    def option?(option)
      content["servers"].any? {|_, settings| settings.has_key?(option)}
    end

    def console_connection(server = nil)
      shelly.console(code_name, server)
    end

    def ssh(options = {})
      conn = console_connection(options[:server])
      exec "ssh #{ssh_options(conn)} -t #{conn['host']} #{options[:command]}"
    end

    def ssh_options(conn = console_connection)
      "-o StrictHostKeyChecking=no -p #{conn['port']} -l #{conn['user']}"
    end

    def rsync(source, destination)
      exec "rsync -avz -e 'ssh #{ssh_options}' --progress #{source} #{destination}"
    end
  end
end
