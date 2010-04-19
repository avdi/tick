$:.unshift(File.expand_path('../../lib', File.dirname(__FILE__)))
require 'rubygems'
require 'shellwords'
require 'stringio'
require 'main'
require 'main/test'
require 'construct'
require 'rack/mount'
require 'servolux'
require 'rack/fake'
require 'open4'

World(Construct::Helpers)

module Helpers

  def read_until(stream, pattern)
    timeout    = 1.0
    start_time = Time.now
    while (Time.now - start_time) < timeout
      Thread.exclusive do
        return stream.string if stream.string.match(pattern)
      end
      sleep 0.1
    end
    stream.string
  end

end

World(Helpers)
World(Open4)

Before do
  @construct = create_construct
end

After do
  @construct.destroy! if @construct.exist?
end
