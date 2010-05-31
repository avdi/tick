Feature: choose a project
  As a developer
  I want to associate a ticketing project with the local project
  So that the correct tickets are shown

  Scenario: choose a project from a list
    Given I am a member of the following projects
      | title     |
      | Project A |
      | Project B |
     And I have logged in to a Git/Tracker project
    When I run "tick project select"
    Then I should see "2. Project B"
    When I enter "2"
     And I run "tick info"
    Then I should see "Project B"
     And I should not see "Project A"
