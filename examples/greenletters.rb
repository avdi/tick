$:.unshift(File.expand_path('../lib', File.dirname(__FILE__)))
require 'greenletters'
require 'logger'

logger = ::Logger.new($stdout)
logger.level = ::Logger::DEBUG
a = Greenletters::Process.new("adventure", :logger => logger)
a.on(:output, "Do you really want to quit now?") do |p, match|
  p.write "yes\n"
end
a.on(:output, "Would you like instructions?") do |p, match|
  p.write "no\n"
end

puts "Starting process"
a.start!

puts "Adding a trigger after startup"
a.on(:output, /food/, :exclusive => false) do |p, match|
  puts "Mmmm, I'm hungry!"
end

a.wait_for(:output, /standing at the end of a road/) do |p, match|
  puts "Matching output:\n\n----#{match[0]}\n----"
  p.write "east\n"
end

puts "I'm entering the building"
a.wait_for(:output, /inside a building/) do |p, match|
  puts "I'm inside the building"
  p.puts "west"
end

begin
  a.wait_for(:output, /in a spaceship/)
rescue => error
  puts "Error caught: #{error.message}"
end

a.puts "quit"

a.wait_for(:exit)

puts "Process exited with status #{a.status}"


