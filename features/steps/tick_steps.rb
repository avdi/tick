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

Given /^I have logged in$/ do
  Given 'my Tracker token is TOKEN'
   When 'I run "tick info"'
   Then 'I should see "Tracker login:"'
   When 'I enter "bob"'
   Then 'I should see "Password:"'
   When 'I enter "xyzzy"'
end

Given /^I am a member of the following projects$/ do |projects|
  @tracker.define do
    get '/services/v3/projects' do
      content_type 'application/xml'
      erubis <<"END", {}, {:projects => projects}
<?xml version="1.0" encoding="UTF-8"?>
<projects type="array">
  <% projects.hashes.each_with_index do |project, index| %>
  <project>
    <id><%= index %></id>
    <name><%= project[:name] %></name>
    <iteration_length type="integer">2</iteration_length>
    <week_start_day>Monday</week_start_day>
    <point_scale>0,1,2,3</point_scale>
    <velocity_scheme>Average of 4 iterations</velocity_scheme>
    <current_velocity>10</current_velocity>
    <initial_velocity>10</initial_velocity>
    <number_of_done_iterations_to_show>12</number_of_done_iterations_to_show>
    <labels>shields,transporter</labels>
    <allow_attachments>true</allow_attachments>
    <public>false</public>
    <use_https>true</use_https>
    <bugs_and_chores_are_estimatable>false</bugs_and_chores_are_estimatable>
    <commit_mode>false</commit_mode>
    <last_activity_at type="datetime">2010/01/16 17:39:10 CST</last_activity_at>
    <memberships>
      <membership>
        <id><%= 1000 + index %></id>
        <person>
          <email>bob@example.org</email>
          <name>J.R. "Bob" Dobbs</name>
          <initials>JRD</initials>
        </person>
        <role>Owner</role>
      </membership>
    </memberships>
    <integrations>
      <integration>
        <id type="integer">3</id>
        <type>Other</type>
        <name>United Federation of Planets Bug Tracker</name>
        <field_name>other_id</field_name>
        <field_label>United Federation of Planets Bug Tracker Id</field_label>
        <active>true</active>
      </integration>
    </integrations>
  </project>
  <% end %>
</projects>

END
    end
  end
end

When /^I run "([^\"]*)"$/ do |command|
  logger = ::Logger.new($stderr)
  logger.level = ::Logger::DEBUG
  command = command.sub(/^tick/, File.join(@bin_dir, 'tick'))
  @process = Greenletters::Process.new(command, :logger => logger)
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
