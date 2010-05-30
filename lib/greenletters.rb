require 'logger'
require 'pty'
require 'forwardable'
require 'stringio'
require 'shellwords'
require 'rbconfig'

# A better expect.rb
#
# Implementation note: because of the way PTY is implemented in Ruby, it is
# possible when executing a quick non-interactive command for PTY::ChildExited
# to be raised before ever getting input/output handles to the child
# process. Without an output handle, it's not possible to read any output the
# process produced. This is obviously undesirable, especially since when a
# command is unexpectedly quick and noninteractive it's usually because there
# was an error and you really want to be able to see what the problem was.
#
# Greenletters' solution to this problem is to wrap every command in a short
# script. The script executes the passed command and on termination, outputs an
# easily recognizable marker string. Then it waits for acknowledgment (a
# newline) before exiting. When Greenletters sees the marker string in the
# output, it automatically performs the acknowledgement and allows the child
# process to finish. By forcing the child process to wait for acknowledgement,
# we guarantee that the child will never exit before we have a chance to look at
# the output.
module Greenletters
  LogicError   = Class.new(::Exception)
  SystemError  = Class.new(RuntimeError)
  TimeoutError = Class.new(SystemError)
  ClientError  = Class.new(RuntimeError)
  StateError   = Class.new(ClientError)
  Process

  def Trigger(event, *args, &block)
    klass = trigger_class_for_event(event)
    klass.new(*args, &block)
  end

  def trigger_class_for_event(event)
    ::Greenletters.const_get("#{event.to_s.capitalize}Trigger")
  end

  class Trigger
    attr_accessor :time_to_live
    attr_accessor :exclusive
    attr_accessor :logger
    attr_accessor :interruption

    alias_method :exclusive?, :exclusive

    def initialize(options={}, &block)
      @block        = block || lambda{}
      @exclusive    = options.fetch(:exclusive) { false }
      @logger       = ::Logger.new($stdout)
      @interruption = :none
    end

    def call(process)
      @block.call(process)
      true
    end
  end

  class OutputTrigger < Trigger
    def initialize(pattern=//, options={}, &block)
      super(options, &block)
      @pattern = pattern
    end

    def to_s
      "output matching #{@pattern.inspect}"
    end

    def call(process)
      data = process.output_buffer.string
      @logger.debug "matching #{@pattern.inspect} against #{data.inspect}"
      if (md = data.match(@pattern))
        @logger.debug "matched #{@pattern.inspect}"
        @block.call(process, md)
        true
      else
        false
      end
    end
  end

  class TimeoutTrigger < Trigger
    def to_s
      "timeout"
    end

    def call(process)
      @block.call(process, process.blocker)
      true
    end
  end

  class ExitTrigger < Trigger
    attr_reader :pattern

    def initialize(pattern=0, options={}, &block)
      super(options, &block)
      @pattern = pattern
    end

    def call(process)
      if pattern === process.status.exitstatus
        @block.call(process, process.status)
        true
      else
        false
      end
    end

    def to_s
      "exit with status #{pattern}"
    end
  end

  class UnsatisfiedTrigger < Trigger
    def to_s
      "unsatisfied wait"
    end

    def call(process)
      @block.call(process, process.interruption, process.blocker)
      true
    end
  end

  class Process
    END_MARKER = '__GREENLETTERS_PROCESS_ENDED__'

    # Shamelessly stolen from Rake
    RUBY_EXT =
      ((Config::CONFIG['ruby_install_name'] =~ /\.(com|cmd|exe|bat|rb|sh)$/) ?
      "" :
      Config::CONFIG['EXEEXT'])
    RUBY       = File.join(
      Config::CONFIG['bindir'],
      Config::CONFIG['ruby_install_name'] + RUBY_EXT).
      sub(/.*\s.*/m, '"\&"')

    extend Forwardable
    include ::Greenletters

    attr_reader   :command      # Command to run in a subshell
    attr_accessor :blocker      # The Trigger currently being waited for, if any
    attr_reader   :input_buffer # Input waiting to be written to process
    attr_reader   :output_buffer # Output ready to be read from process
    attr_reader   :status        # :not_started -> :running -> :ended -> :exited
    attr_reader   :cwd          # Working directory for the command

    def_delegators :input_buffer, :puts, :write, :print, :printf, :<<
    def_delegators :output_buffer, :read, :readpartial, :read_nonblock, :gets,
                                   :getline
    def_delegators  :blocker, :interruption, :interruption=

    def initialize(*args)
      options        = args.pop if args.last.is_a?(Hash)
      @command       = args
      @triggers      = []
      @blocker       = nil
      @input_buffer  = StringIO.new
      @output_buffer = StringIO.new
      @env           = options.fetch(:env) {{}}
      @cwd           = options.fetch(:cwd) {Dir.pwd}
      @logger   = options.fetch(:logger) {
        l = ::Logger.new($stdout)
        l.level = ::Logger::WARN
        l
      }
      @state         = :not_started
      @shell         = options.fetch(:shell) { '/bin/sh' }
      @transcript    = options.fetch(:transcript) {
        t = Object.new
        def t.<<(*)
          # NOOP
        end
        t
      }
    end

    def on(event, *args, &block)
      t = add_trigger(event, *args, &block)
    end

    def wait_for(event, *args, &block)
      raise "Already waiting for #{blocker}" if blocker
      t = add_blocking_trigger(event, *args, &block)
      process_events
    rescue
      unblock!
      triggers.delete(t)
      raise
    end

    def add_trigger(event, *args, &block)
      t = Trigger(event, *args, &block)
      t.logger = @logger
      triggers << t
      @logger.debug "added trigger on #{t}"
      t
    end

    def prepend_trigger(event, *args, &block)
      t = Trigger(event, *args, &block)
      t.logger = @logger
      triggers.unshift(t)
      @logger.debug "prepended trigger on #{t}"
      t
    end


    def add_blocking_trigger(event, *args, &block)
      t = add_trigger(event, *args, &block)
      t.time_to_live = 1
      @logger.debug "waiting for #{t}"
      self.blocker = t
      t
    end

    def start!
      raise StateError, "Already started!" unless not_started?
      @logger.debug "installing end marker handler for #{END_MARKER}"
      prepend_trigger(:output, /#{END_MARKER}/, :exclusive => false, :time_to_live => 1) do |process, data|
        handle_end_marker
      end
      handle_child_exit do
        cmd = wrapped_command
        @logger.debug "executing #{cmd.join(' ')}"
        merge_environment(@env) do
          @logger.debug "command environment:\n#{ENV.inspect}"
          @output, @input, @pid = PTY.spawn(*cmd)
        end
        @state = :running
        @logger.debug "spawned pid #{@pid}"
      end
    end

    def flush_output_buffer!
      @logger.debug "flushing output buffer"
      @output_buffer.string = ""
      @output_buffer.rewind
    end

    def alive?
      ::Process.kill(0, @pid)
      true
    rescue Errno::ESRCH, Errno::ENOENT
      false
    end

    def blocked?
      @blocker
    end

    def running?
      @state == :running
    end

    def not_started?
      @state == :not_started
    end

    def exited?
      @state == :exited
    end

    # Have we seen the end marker yet?
    def ended?
      @state == :ended
    end

    private

    attr_reader :triggers

    def wrapped_command
      [RUBY,
        '-C', cwd,
        '-e', "system(*#{command.inspect})",
        '-e', "puts(#{END_MARKER.inspect})",
        '-e', "gets",
        '-e', "exit $?.exitstatus"
      ]
    end

    def process_events
      raise StateError, "Process not started!" if not_started?
      handle_child_exit do
        while blocked?
          @logger.debug "select()"
          input_handles  = input_buffer.string.empty? ? [] : [@input]
          output_handles = [@output]
          error_handles  = [@input, @output]
          @logger.debug "select() on #{[output_handles, input_handles, error_handles].inspect}"
          ready_handles = IO.select(
            output_handles, input_handles, error_handles, 1.0)
          if ready_handles.nil?
            process_timeout
          else
            ready_outputs, ready_inputs, ready_errors = *ready_handles
            ready_errors.each do |handle| process_error(handle) end
            ready_outputs.each do |handle| process_output(handle) end
            ready_inputs.each do |handle| process_input(handle) end
          end
        end
      end
    end

    def process_input(handle)
      @logger.debug "input ready #{handle.inspect}"
      handle.write(input_buffer.string)
      @logger.debug format_output_for_log(input_buffer.string)
      @logger.debug "wrote #{input_buffer.string.size} bytes"
      input_buffer.string = ""
    end

    def process_output(handle)
      @logger.debug "output ready #{handle.inspect}"
      result = handle.readpartial(1024,output_buffer.string)
      @transcript << result
      @logger.debug format_input_for_log(output_buffer.string)
      @logger.debug "read #{result.size} bytes"
      handle_triggers(:output)
      flush_triggers!(OutputTrigger) if ended?
      flush_output_buffer! unless ended?
    end

    def collect_remaining_output
      if @output.nil?
        @logger.debug "unable to collect output for missing output handle"
        return
      end
      @logger.debug "collecting remaining output"
      while data = @output.read_nonblock(1024, output_buffer.string)
        @logger.debug "read #{data.size} bytes"
      end
    rescue EOFError, Errno::EIO => error
      @logger.debug error.message
    end

    def wait_for_child_to_die
      # Soon we should get a PTY::ChildExited
      while running? || ended?
        @logger.debug "waiting for child #{@pid} to die"
        sleep 0.1
      end
    end

    def process_error(handle)
      @logger.debug "error on #{handle.inspect}"
      raise NotImplementedError, "process_error()"
    end

    def process_timeout
      @logger.debug "timeout"
      handle_triggers(:timeout)
      process_interruption(:timeout)
    end

    def handle_exit(status=status_from_waitpid)
      return false if exited?
      @logger.debug "handling exit of process #{@pid}"
      @state  = :exited
      @status = status
      handle_triggers(:exit)
      if status == 0
        process_interruption(:exit)
      else
        process_interruption(:abnormal_exit)
      end
    end

    def status_from_waitpid
      @logger.debug "waiting for exist status of #{@pid}"
      ::Process.waitpid2(@pid)[1]
    end

    def handle_triggers(event)
      klass = trigger_class_for_event(event)
      matches = 0
      triggers.grep(klass).each do |t|
        @logger.debug "checking #{event} against #{t}"
        if t.call(self)         # match
          matches += 1
          @logger.debug "match trigger #{t}"
          if blocker.equal?(t)
            unblock!
          end
          if t.time_to_live
            if t.time_to_live > 1
              t.time_to_live -= 1
              @logger.debug "trigger ttl reduced to #{t.time_to_live}"
            else
              triggers.delete(t)
              @logger.debug "trigger removed"
            end
          end
          break if t.exclusive?
        else
          @logger.debug "no match"
        end
      end
      matches > 0
    end

    def handle_end_marker
      return false if ended?
      @logger.debug "end marker found"
      output_buffer.string.gsub!(/#{END_MARKER}\s*/, '')
      @state = :ended
      @logger.debug "end marker expunged from output buffer"
      @logger.debug "acknowledging end marker"
      self.puts
    end

    def unblock!
      @logger.debug "unblocked"
      triggers.delete(@blocker)
      @blocker = nil
    end

    def handle_child_exit
      handle_eio do
        yield
      end
    rescue PTY::ChildExited => error
      @logger.debug "caught PTY::ChildExited"
      collect_remaining_output
      handle_exit(error.status)
    end

    def handle_eio
      yield
    rescue Errno::EIO => error
      @logger.debug "Errno::EIO caught"
      wait_for_child_to_die
    end

    def flush_triggers!(kind)
      @logger.debug "flushing triggers matching #{kind}"
      triggers.delete_if{|t| kind === t}
    end

    def merge_environment(new_env)
      old_env = new_env.inject({}) do |old, (key, value)|
        old[key] = ENV[key]
        ENV[key] = value
        old
      end
      yield
    ensure
      old_env.each_pair do |key, value|
        if value.nil? then ENV.delete(key) else ENV[key] = value end
      end
    end

    def process_interruption(reason)
      if blocked?
        self.interruption = reason
        unless handle_triggers(:unsatisfied)
          raise SystemError, "Interrupted (#{reason}) while waiting for #{blocker}"
        end
        unblock!
      end
    end

    def format_output_for_log(text)
      "\n" + text.split("\n").map{|l| ">> #{l}"}.join("\n")
    end

    def format_input_for_log(text)
      "\n" + text.split("\n").map{|l| "<< #{l}"}.join("\n")
    end
  end
end
