module ProjectHelpers
  def project_names
    @project_names ||= []
  end

  def tracker_project_xml(name="TEST PROJECT", id=1)
    <<"EOF"
      <project>
        <id>#{id}</id>
        <name>#{name}</name>
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
            <id>1006</id>
            <person>
              <email>kirkybaby@earth.ufp</email>
              <name>James T. Kirk</name>
              <initials>JTK</initials>
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
EOF
  end

  def tracker_project_list_xml(*names)
    names = names.empty? ? project_names : names
    projects_xml = ""
    project_names.each_with_index do |n, i|
      projects_xml << tracker_project_xml(n,i) << "\n"
    end

    xml = <<"EOF"
  <?xml version="1.0" encoding="UTF-8"?>
    <projects type="array">
      #{projects_xml}
    </projects>
EOF
  end

  def tracker_ticket_list_xml(tickets)
    tickets_xml = tickets.map{|ticket|
      tracker_ticket_xml(ticket)
    }.join("\n")
    <<"EOF"
  <stories type="array" count="#{tickets.size}" total="#{tickets.size}">
    #{tickets_xml}
  </stories>
EOF
  end

  def tracker_ticket_xml(ticket)
<<"EOF"
    <story>
      <id type="integer">#{ticket[:id]}</id>
      <project_id type="integer">PROJECT_ID</project_id>
      <story_type>feature</story_type>
      <url>http://www.pivotaltracker.com/story/show/#{ticket[:id]}</url>
      <estimate type="integer">1</estimate>
      <current_state>accepted</current_state>
      <description></description>
      <name>#{ticket[:title]}</name>
      <requested_by>James Kirk</requested_by>
      <owned_by>#{ticket[:owner]}</owned_by>
      <created_at type="datetime">2008/12/10 00:00:00 UTC</created_at>
      <accepted_at type="datetime">2008/12/10 00:00:00 UTC</accepted_at>
      <labels>label 1,label 2,label 3</labels>
    </story>
EOF
  end
end

World(ProjectHelpers)

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

Given /^I have logged in to a Git\/Tracker project$/ do
  Given 'I am in a Git project'
    And 'my Tracker token is TOKEN123'
    And 'the Tracker server is available'
   When 'I run "tick login"'
   Then 'I should see "Tracker login:"'
   When 'I enter "bob"'
   Then 'I should see "Password:"'
   When 'I enter "xyzzy"'
   Then 'I should see "TOKEN123"'
   And 'the command should exit successfully'
end

Given /^I am a member of the following projects$/ do |projects|
  projects.hashes.each do |project|
    project_names << project[:title]
  end
end

Given /^the Tracker server is available$/ do
  list_xml = tracker_project_list_xml
  @tracker.define do
    get '/services/v3/projects' do
      content_type 'application/xml'
      list_xml
    end
  end
  @tracker.start
end

Given /^my tracker login is "([^\"]*)"$/ do |login|
  @login = login
end

Given /^project "([^\"]*)" with current tickets:$/ do |name, tickets|
  project_names << name

  ticket_list_xml = tracker_ticket_list_xml(tickets.hashes)
  project_index   = project_names.index(name)
  @tracker.define do
    get "/services/v3/projects/#{project_index}/iterations/current" do
      content_type 'application/xml'

      <<"EOF"
<?xml version="1.0" encoding="UTF-8"?>
<iterations type="array">
  <iteration>
    <id type="integer">21</id>
    <number type="integer">21</number>
    <start type="datetime">2010/06/01 08:00:00 UTC</start>
    <finish type="datetime">2010/06/08 08:00:00 UTC</finish>
    #{ticket_list_xml}
  </iteration>
</iterations>
EOF
    end
  end

end

Given /^I have chosen project "([^\"]*)"$/ do |project_name|
  When "I run \"tick select-project '#{project_name}'\""
end

When /^I run "([^\"]*)"$/ do |command|
  if @process
    @process.wait_for(:exit)
  end
  command = command.sub(/^tick/, File.join(@bin_dir, 'tick'))
  command << " -d"
  log_path     = (@tmpdir + 'commands.log').to_s
  logger       = ::Logger.new(log_path)
  logger.level = ::Logger::DEBUG
  logger << "\n\n*** Running command `#{command}`\n"
  @transcript   = ""
  @process = Greenletters::Process.new(command,
    :logger => logger,
    :env    => {'TICK_TRACKER_BASE_URI' =>
      "http://#{@tracker.host}:#{@tracker.port}"},
    :transcript => @transcript,
    :cwd        => @construct.to_s)
  @process.on(:unsatisfied) do |process, reason, blocker|
    configuration = if (@construct + '.tick').exist?
                      (@construct + '.tick').read
                    else
                      "<No configuration>"
                    end
    raise "#{reason} while waiting for #{blocker}\nCommand logged to #{log_path}" \
          "\nTranscript:\n\n#{@transcript}\n\n" \
          "Server output:\n\n#{@tracker.output}\n\n" \
          "Configuration:\n\n#{configuration}\n\n" \
          "---------------------------------------------------------------------"
  end
  @process.start!
end

Then /^I should see "([^\"]*)"$/ do |pattern|
  @process.wait_for(:output, Regexp.new(pattern, Regexp::IGNORECASE))
end

Then /^I should not see "([^\"]*)"$/ do |pattern|
  @process.on(:output, Regexp.new(pattern, Regexp::IGNORECASE)) do
    raise "Expected not to see #{pattern}, but saw it in:\n\n#{@transcript}"
  end
end

When /^I enter "([^\"]*)"$/ do |response|
  @process.puts response
end

Then /^the command should exit successfully$/ do
  @process.wait_for(:exit, 0)
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
