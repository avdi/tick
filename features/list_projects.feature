Feature: list projects
  As a developer
  I want to see projects I have access to
  So that I can pick one to work on

  Scenario: show my projects
    Given I am a member of the following projects
      | title     |
      | Project A |
      | Project C |
     And I have logged in to a Git/Tracker project
    When I run "tick project list"
    Then I should see "Project A"
     And I should see "Project C"
