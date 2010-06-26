Feature: list tickets
  As a developer
  I want to list tickets associated with the current project
  So that I can pick one to work on

  Scenario: list tickets
    Given my tracker login is "thedude"
    Given project "MYPROJECT" with current tickets:
      | title           | owner         | id            |
      | Ticket A        | thedudue      | 123           |
      | Ticket B        |               | 456           |
      | Ticket C        | thedude       | 789           |
     And I have logged in to a Git/Tracker project
     And I have chosen project "MYPROJECT"
    When I run "tick list"
    Then I should not see "Ticket B"
     And I should see "Ticket A"
     And I should see "Ticket C"
