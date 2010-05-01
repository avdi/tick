Feature: list projects
  As a developer
  I want to see projects I have access to
  So that I can pick one to work on

  Scenario: show my projects
    Given I have logged in
      And I am a member of the following projects
      | title     |
      | Project A |
      | Project C |
    When I run "tick list"
    Then I should see "Project A"
     And I should see "Project C"
