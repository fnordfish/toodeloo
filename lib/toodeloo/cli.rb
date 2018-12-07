require "logger"

module Toodeloo
  class Cli
    attr_reader :signal_handlers, :error_handlers, :logger

    def initialize(signal_handlers: {}, error_handlers: [], kill_on_error: true, logger: nil)
      @signals = DEFAULT_SIGNAL_HANDLERS.keys | signal_handlers.keys.map { |k| k.to_s.upcase }
      @signal_handlers = signal_handlers
      @error_handlers = DEFAULT_ERROR_HANDLERS + error_handlers
      @error_handlers << KILL_ON_ERROR_HANDLER if kill_on_error
      @logger = logger || ::Logger.new(STDOUT, level: :debug)
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
        logger.debug "done reading"
      rescue Interrupt
        logger.info 'Shutting down'
        stop
        # Explicitly exit so busy Processor threads can't block
        # process shutdown.
        logger.info "Bye!"
        exit(0)
      end
    end

    def kill(sig = "TERM")
      Process.kill(sig, Process.pid)
    end

    def stopped?
      @done
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
      logger.debug "Got #{sig} signal"

      handler = @signal_handlers[sig]
      if handler
        handler.call(self)
      end

      handy = DEFAULT_SIGNAL_HANDLERS[sig]
      if handy
        handy.call(self)
      elsif !handler
        logger.info { "No signal handler for #{sig}" }
      end
    end

    DEFAULT_ERROR_HANDLERS = [
      ->(cli, ex) {
        msg = +"#{ex.class.name}: #{ex.message}"
        msg << "\n" << ex.backtrace.join("\n") unless ex.backtrace.nil?
        cli.logger.warn(msg)
      }
    ]

    KILL_ON_ERROR_HANDLER = ->(cli, ex) { cli.kill }

    def handle_exception(ex)
      error_handlers.each do |handler|
        begin
          handler.call(self, ex)
        rescue => ex
          logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
          logger.error ex
          logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
        end
      end
    end
  end
end
