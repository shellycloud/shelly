require "spec_helper"
require "shelly/app"

describe Shelly::App do
  before do
    FileUtils.mkdir_p("/projects/foo")
    Dir.chdir("/projects/foo")
    @client = mock(:api_url => "https://api.example.com", :shellyapp_url => "http://shellyapp.example.com")
    Shelly::Client.stub(:new).and_return(@client)
    @app = Shelly::App.new
    @app.code_name = "foo-staging"
  end

  describe ".guess_code_name" do
    it "should return name of current working directory" do
      Shelly::App.guess_code_name.should == "foo"
    end
  end

  describe "#users" do
    it "should fetch app's users" do
      @client.should_receive(:app_users).with("foo-staging")
      @app.users
    end
  end

  describe "#ips" do
    it "should get app's ips" do
      @client.should_receive(:app_ips).with("foo-staging")
      @app.ips
    end
  end

  describe "#add_git_remote" do
    before do
      @app.stub(:git_url).and_return("git@git.shellycloud.com:foo-staging.git")
      @app.stub(:system)
    end

    it "should try to remove existing git remote" do
      @app.should_receive(:system).with("git remote rm production > /dev/null 2>&1")
      @app.add_git_remote
    end

    it "should add git remote with proper name and git repository" do
      @app.should_receive(:system).with("git remote add production git@git.shellycloud.com:foo-staging.git")
      @app.add_git_remote
    end
  end

  describe "#configs" do
    it "should get configs from client" do
      @client.should_receive(:app_configs).with("foo-staging")
      @app.configs
    end

    it "should return only user config files" do
      @client.should_receive(:app_configs).with("foo-staging").and_return([])
      @app.user_configs
    end

    it "should return only shelly genereted config files" do
      @client.should_receive(:app_configs).with("foo-staging").and_return([])
      @app.shelly_generated_configs
    end
  end

  describe "#generate_cloudfile" do
    it "should return generated cloudfile" do
      user = mock(:email => "bob@example.com")
      @app.stub(:current_user).and_return(user)
      @app.databases = %w(postgresql mongodb)
      @app.domains = %w(foo-staging.winniecloud.com foo.example.com)
      FakeFS.deactivate!
      expected = <<-config
foo-staging:
  ruby_version: 1.9.2 # 1.9.2 or ree
  environment: production # RAILS_ENV
  monitoring_email:
    - bob@example.com
  domains:
    - foo-staging.winniecloud.com
    - foo.example.com
  servers:
    app1:
      size: large
      thin: 4
      # whenever: on
      # delayed_job: 1
    postgresql:
      size: large
      databases:
        - postgresql
    mongodb:
      size: large
      databases:
        - mongodb
config
      @app.generate_cloudfile.strip.should == expected.strip
    end
  end

  describe "#create_cloudfile" do
    before do
      @app.stub(:generate_cloudfile).and_return("foo-staging:")
    end

    it "should create file if Cloudfile doesn't exist" do
      File.exists?("/projects/foo/Cloudfile").should be_false
      @app.create_cloudfile
      File.exists?("/projects/foo/Cloudfile").should be_true
    end

    it "should append content if Cloudfile exists" do
      File.open("/projects/foo/Cloudfile", "w") { |f| f << "foo-production:\n" }
      @app.create_cloudfile
      File.read("/projects/foo/Cloudfile").strip.should == "foo-production:\nfoo-staging:"
    end
  end

  describe "#cloudfile_path" do
    it "should return path to Cloudfile" do
      @app.cloudfile_path.should == "/projects/foo/Cloudfile"
    end
  end

  describe "#open_billing_page" do
    it "should open browser window" do
      user = mock(:token => "abc", :email => nil, :password => nil, :config_dir => "~/.shelly")
      @app.stub(:current_user).and_return(user)
      url = "#{@app.shelly.shellyapp_url}/login?api_key=abc&return_to=/apps/foo-staging/edit_billing"
      Launchy.should_receive(:open).with(url)
      @app.open_billing_page
    end
  end

  describe "#start & #stop" do
    it "should start cloud" do
      @client.should_receive(:start_cloud).with("foo-staging")
      @app.start
    end

    it "should stop cloud" do
      @client.should_receive(:stop_cloud).with("foo-staging")
      @app.stop
    end
  end

  describe "#logs" do
    it "should list logs" do
      @client.should_receive(:cloud_logs).with("foo-staging")
      @app.logs
    end
  end

  describe "#create" do
    context "without providing domain" do
      it "should create the app on shelly cloud via API client" do
        @app.code_name = "fooo"
        attributes = {
          :code_name => "fooo",
          :name => "fooo",
          :domains => nil
        }
        @client.should_receive(:create_app).with(attributes).and_return("git_url" => "git@git.shellycloud.com:fooo.git",
          "domains" => %w(fooo.shellyapp.com))
        @app.create
      end

      it "should assign returned git_url, domains, ruby_version and environment" do
        @client.stub(:create_app).and_return("git_url" => "git@git.example.com:fooo.git",
          "domains" => ["fooo.shellyapp.com"], "ruby_version" => "1.9.2", "environment" => "production")
        @app.create
        @app.git_url.should == "git@git.example.com:fooo.git"
        @app.domains.should == ["fooo.shellyapp.com"]
        @app.ruby_version.should == "1.9.2"
        @app.environment.should == "production"
      end
    end

    context "with providing domain" do
      it "should create the app on shelly cloud via API client" do
        @app.code_name = "boo"
        @app.domains = ["boo.shellyapp.com", "boo.example.com"]
        attributes = {
          :code_name => "boo",
          :name => "boo",
          :domains => %w(boo.shellyapp.com boo.example.com)
        }
        @client.should_receive(:create_app).with(attributes).and_return("git_url" => "git@git.shellycloud.com:fooo.git",
          "domains" => %w(boo.shellyapp.com boo.example.com))
        @app.create
      end

      it "should assign returned git_url and domain" do
        @client.stub(:create_app).and_return("git_url" => "git@git.example.com:fooo.git",
          "domains" => %w(boo.shellyapp.com boo.example.com))
        @app.create
        @app.domains.should == %w(boo.shellyapp.com boo.example.com)
      end
    end
  end
end

