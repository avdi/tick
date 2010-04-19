$:.unshift(File.expand_path('../lib', File.dirname(__FILE__)))
require 'rack/fake'

fake = Rack::Fake.new("hello", :port => 8700) do 
  get '/hello' do
    "Hello, world"
  end

  get '/goodbye' do
    "Goodbye, world"
  end
end

puts "Starting fake"
fake.start
puts "Fake started"

host = fake.host
port = fake.port

puts "Host: #{host}; Port: #{port}"
puts "Output: #{fake.output}"

puts "Using Net::HTTP:"
Net::HTTP.get_print(host, '/hello', port)
puts

url = "http://#{host}:#{port}/goodbye"
puts "Using curl #{url}"
puts `curl #{url}`

puts "Press enter to stop"
gets

fake.stop
