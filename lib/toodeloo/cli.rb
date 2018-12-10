require "logger"

module Toodeloo
  class Cli
    attr_reader :signal_handlers, :error_handlers, :logger

    # @param signal_handlers: {String => Proc} [Hash] Uppercase signal names as String mapping to anything call-able which receives this instance as argument.
    # @param error_handlers: DEFAULT_ERROR_HANDLERS [Array] Anything call-able which receives this instance as first argument and the raised exception as second argument.
    # @param kill_on_error: true [Boolean] Whether to shut down the current process after all error handlers have been run.
    # @param logger: ::Logger [Logger|nil] A custom Logger to log life-cycle informations/warning to. Set to `nil` to disable logging. Default to log to STDOUT with log-level :debug
    #
    # @return [type] [description]
    def initialize(signal_handlers: {}, error_handlers: DEFAULT_ERROR_HANDLERS, kill_on_error: true, logger: ::Logger.new(STDOUT, level: :debug))
      @signals = DEFAULT_SIGNAL_HANDLERS.keys | signal_handlers.keys.map { |k| k.to_s.upcase }
      @signal_handlers = signal_handlers
      @error_handlers = DEFAULT_ERROR_HANDLERS
      @error_handlers << KILL_ON_ERROR_HANDLER if kill_on_error
      @logger = logger
      @done = false
      @thread = nil
    end

    def run(as_loop = false, &block)
      self_read, self_write = IO.pipe

      @signals.each do |sig|
        begin
          trap(sig) do
            self_write.write("#{sig}\n")
          end
        rescue ArgumentError
          STDERR.puts "Signal #{sig} not supported"
        end
      end

      begin
        if as_loop
          run_loop(&block)
        else
          run_once(&block)
        end

        while readable_io = IO.select([self_read])
          signal = readable_io.first[0].gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        logger&.info { log_messages[:shutting_down] }
        stop
        # Explicitly exit so busy Processor threads can't block
        # process shutdown.
        logger&.info { log_messages[:exiting] }
        exit(0)
      end
    end

    def kill(sig = "TERM")
      Process.kill(sig, Process.pid)
    end

    def stopped?
      @done
    end

    DEFAULT_LOG_MESSAGES = {
      shutting_down: "Shutting down",
      exiting: "Bye!",
      signal_trapped: "Got %{sig} signal",
      no_signal_handler: "No signal handler for %{sig}",
      exception_in_handler: "!!! ERROR HANDLER THREW AN ERROR !!!\n%{class}: %{message}\n%{backtrace}"
    }
    def log_messages
      @log_messages ||= DEFAULT_LOG_MESSAGES.dup
    end

    protected

    def watchdog
      yield(self)
    rescue Exception => ex
      handle_exception(ex)
      raise ex
    end

    def safe_thread(&block)
      Thread.new do
        Thread.current.report_on_exception = false
        watchdog(&block)
      end
    end

    def run_once(&block)
      @thread ||= safe_thread do
        yield(self)
        self.kill
      end
    end

    def run_loop(&block)
      @thread ||= safe_thread do
        while !@done
          yield(self)
        end
      end
    end

    def stop
      @done = true
      if @thread
        t = @thread
        @thread = nil
        t.value
      end
    end

    DEFAULT_SIGNAL_HANDLERS = {
      # Ctrl-C in terminal
      'INT' => ->(cli) { raise Interrupt },
      # TERM is the signal that Sidekiq must exit.
      # Heroku sends TERM and then waits 30 seconds for process to exit.
      'TERM' => ->(cli) { raise Interrupt }
    }
    def handle_signal(sig)
      logger&.debug { sprintf(log_messages[:signal_trapped], sig: sig) }

      handler = @signal_handlers[sig]
      if handler
        handler.call(self)
      end

      handy = DEFAULT_SIGNAL_HANDLERS[sig]
      if handy
        handy.call(self)
      elsif !handler
        logger&.info { sprintf(log_messages[:no_signal_handler], sig: sig) }
      end
    end

    DEFAULT_ERROR_HANDLERS = [
      ->(cli, ex) {
        msg = +"#{ex.class.name}: #{ex.message}"
        msg << "\n" << ex.backtrace.join("\n") unless ex.backtrace.nil?
        cli.logger&.warn(msg)
        cli.exit_status = false
      }
    ]

    KILL_ON_ERROR_HANDLER = ->(cli, ex) { cli.kill }

    def handle_exception(ex)
      error_handlers.each do |handler|
        begin
          handler.call(self, ex)
        rescue => ex
          msg = sprintf(
            log_messages[:exception_in_handler],
            class: ex.class.name,
            message: ex.message,
            backtrace: ex.backtrace&.join("\n")
          )
        end
      end
    end
  end
end
