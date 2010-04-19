Before do
  @bin_dir = File.expand_path('../../bin', File.dirname(__FILE__))
  @executable = File.join(@bin_dir, 'tick')
  @tracker = Rack::Fake.new('pivotal-tracker') do
    helpers do

      def protected!
        unless authorized?
          response['WWW-Authenticate'] = %(Basic realm="Pivotal")
          throw(:halt, [401, "Not authorized\n"])
        end
      end

      def authorized?
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)
        @auth.provided? && @auth.basic? && 
          @auth.credentials && @auth.credentials == ['bob', 'xyzzy']
      end
      
    end
  end
end

After do
  @tracker.stop
end

Given /^my Tracker token is (\w+)$/ do |token|
    body = <<"END"
<?xml version="1.0" encoding="UTF-8"?>
  <token>
    <guid>#{token}</guid>
    <id type="integer">1</id>
  </token>
END
  
  @tracker.define do
    get '/services/v3/tokens/active' do
      protected!
      body
    end
  end
end

Given /^I am in a Git project/ do
  @construct.directory '.git'
end

module TestMain
  def self.Main(&block)
    throw(:main, block)
  end
end

When /^I run "([^\"]*)"$/ do |command|
  @stdin  = StringIO.new
  @stdout = StringIO.new
  @stderr = StringIO.new
  @command = command.sub(/^tick/, @executable)
  @tracker.start do
    @process = background(
      @command, 
      :cwd     => @construct.to_s,
      :stdin   => @stdin,
      :stdout  => @stdout,
      :stderr  => @stderr,
      :timeout => 4.0)
  end

  # @argv   = Shellwords.shellwords(command.sub(/^tick\s*/,''))
  # @stdin  = StringIO.new
  # @stdout = StringIO.new
  # @stderr = StringIO.new
  # @ui     = stub("UI")
  # main_code = catch(:main) do
  #   TestMain.class_eval(
  #     File.read(
  #       File.expand_path('../../bin/tick', File.dirname(__FILE__))),
  #     File.expand_path('../../bin/tick', File.dirname(__FILE__)),1)
  # end
  # @main = Main.test(
  #   :argv   => @argv, 
  #   :stdin  => @stdin, 
  #   :stderr => @stderr, 
  #   :stdout => @stdout, 
  #   :env    => (@env || {}), &main_code)
end

Then /^I should see "([^\"]*)"$/ do |pattern|
  output = read_until(@stdout, pattern)
  output.should match(pattern)
end

When /^I enter "([^\"]*)"$/ do |response|
  @stdout.rewind
  @stdout.string = ""
  @stdin.rewind
  @stdin.string = response + "\n"
end

After do
  begin
    if @process
      @process.join
    end
    if @stderr
      @stderr.string.should == ""
    end
  ensure
    if @tracker
      @tracker.stop
    end
  end
end
