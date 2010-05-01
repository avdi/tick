$:.unshift(File.expand_path('../../lib', File.dirname(__FILE__)))
require 'rubygems'
require 'shellwords'
require 'stringio'
require 'main'
require 'main/test'
require 'construct'
require 'servolux'
require 'rack/fake'
require 'greenletters'
require 'open4'

World(Construct::Helpers)

module Helpers
end

World(Helpers)

Before do
  @construct = create_construct
end

After do
  @construct.destroy! if @construct.exist?
end
