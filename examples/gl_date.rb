$:.unshift(File.expand_path('../lib', File.dirname(__FILE__)))
require 'greenletters'
require 'logger'

logger = ::Logger.new($stdout)
logger.level = ::Logger::DEBUG
a = Greenletters::Process.new("date", :logger => logger)
a.on(:output) do |process, match_data|
  puts "OUTPUT: #{process.read}"
end
a.start!
a.wait_for(:exit)
