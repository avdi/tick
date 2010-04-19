require 'rack'
require 'sinatra'
require 'servolux'
require 'logger'
require 'socket'
require 'tmpdir'
require 'pathname'

module Rack

  # A tame little web server, handy for faking out web services.
  # See http://xunitpatterns.com/Fake%20Object.html
  class Fake
    BASE_PORT = 8501

    def self.fakes
      (@fakes ||= [])
    end

    attr_reader :host
    attr_reader :port
    attr_reader :tmpdir

    def initialize(name, options={}, &block)
      @definition_blocks = []
      @definition_blocks.push(block) if block
      self.class.fakes << self
      @port     = options.fetch(:port)    { auto_port                }
      @host     = options.fetch(:host)    { "127.0.0.1"              }
      handler   = options.fetch(:handler) { 'webrick'                }
      @name           = "rack-fake-#{name}-#{@port}-#{Process.pid}"
      @tmpdir         = Pathname(Dir.tmpdir) + Pathname(@name)
      @logfile        = @tmpdir + 'server.log'
      @pidfile        = @tmpdir + 'server.pid'
      @daemon_logfile = @tmpdir + 'control.log'
      @tmpdir.mkpath
      pidfile   = @pidfile
      logfile   = @logfile
      port      = self.port
      host      = self.host
      app_maker = method(:app)
      startup_command = lambda  do
        pidfile.open('w+') do |f| f.puts Process.pid end
        log_file = logfile.open('w+') do |log_file|
          log_file.sync = true
          $stderr = log_file
          $stdout = log_file
          Rack::Handler.get(handler).
            run(app_maker.call, :Port => port, :Host => host)
        end
        at_exit do
          stop
        end
      end
      @server = Servolux::Daemon.new(
        :name            => @name,
        :logger          => ::Logger.new(@daemon_logfile.to_s),
        :pid_file        => @pidfile.to_s,
        :startup_command => startup_command, 
        :log_file        => @logfile.to_s,
        :look_for        => port.to_s)
    end

    def define(&block)
      definition_blocks.push(block)
    end

    def auto_port
      BASE_PORT + self.class.fakes.index(self)
    end

    def output
      @logfile.read
    end

    def start
      @server.startup(false)
      if block_given?
        yield(self)
        stop
      end
    end

    def stop
      @server.shutdown
      @tmpdir.rmtree if @tmpdir.exist?
    end

    def make_application(*blocks)
      klass = Class.new(Sinatra::Base)
      blocks.each do |block| 
        klass.module_eval(&block)
      end
      klass.new
    end

    private

    attr_reader :definition_blocks

    def app
      @app ||= make_application(*definition_blocks)
    end
  end
end
