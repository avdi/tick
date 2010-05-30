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
require 'pathname'

World(Construct::Helpers)

module Helpers
end

World(Helpers)

Before do
  @construct = create_construct
  @tmpdir    = (Pathname(__FILE__).dirname + '..' + '..' + 'tmp').expand_path
  @tmpdir.mkpath
end

After do
  @construct.destroy! if @construct.exist?
end
