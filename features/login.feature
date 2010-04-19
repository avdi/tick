Feature: login
  As a developer
  I want to login to my ticketing system
  So that I can interact with it from the command line

  Scenario: log in and show token
    Given my Tracker token is TOKEN
      And I am in a Git project
     When I run "tick info"
     Then I should see "Tracker login:"
     When I enter "bob"
     Then I should see "Password:"
     When I enter "xyzzy"
     Then I should see "TOKEN"
