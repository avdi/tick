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
  @process = Greenletters::Process.new(command)
  @process.start!
end

Then /^I should see "([^\"]*)"$/ do |pattern|
  @process.wait_for(:output, pattern)
end

When /^I enter "([^\"]*)"$/ do |response|
  @process.puts response
end

After do
  begin
    if @process
      @process.wait_for(:exit)
    end
  ensure
    if @tracker
      @tracker.stop
    end
  end
end
