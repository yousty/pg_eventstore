# frozen_string_literal: true

module PgEventstore
  class BasicRunner
    include Extensions::CallbacksExtension

    attr_reader :state

    # @param run_interval [Integer, Float] seconds. Determines how often to run async task using :process_async callback
    def initialize(run_interval, async_shutdown_time)
      @run_interval = run_interval
      @async_shutdown_time = async_shutdown_time
      @state = ObjectState.new
      @mutex = Thread::Mutex.new
    end

    def start
      synchronize do
        return self unless @state.initial? || @state.stopped?

        callbacks.run_callbacks(:before_runner_started)
        _start
      end
      self
    end

    def stop
      synchronize do
        return self unless @state.running? || @state.dead?

        @runner&.exit
        @runner = nil
        @state.stopped!
        callbacks.run_callbacks(:after_runner_stopped)
      end
      self
    end

    def stop_async
      synchronize do
        return self unless @state.running? || @state.dead?

        @state.halting!
        Thread.new do
          stopping_at = Time.now.utc
          halt = false
          loop do
            synchronize do
              # Give the runner up to @async_shutdown_time seconds for graceful shutdown
              @runner&.exit if Time.now.utc - stopping_at > @async_shutdown_time

              unless @runner&.alive?
                @state.stopped!
                @runner = nil
                callbacks.run_callbacks(:after_runner_stopped)
                halt = true
              end
            end
            break if halt
            sleep 0.1
          end
        end
        self
      end
    end

    def restore
      synchronize do
        return self unless @state.dead?

        @runner = nil
        @state.stopped!
        callbacks.run_callbacks(:before_runner_restored)
        _start
      end
    end

    # Wait until runner switch the state to either "stopped" or "dead". This operation is synchronous.
    # @return [void]
    def wait_for_finish
      loop do
        break unless @state.halting? || @state.running?

        sleep 0.1
      end
      self
    end

    private

    def synchronize
      @mutex.synchronize { yield }
    end

    def _start
      @state.running!
      @runner = Thread.new do
        Thread.current.abort_on_exception = false
        Thread.current.report_on_exception = false

        loop do
          Thread.current.exit unless @state.running?
          sleep @run_interval

          callbacks.run_callbacks(:process_async)
        end
      rescue => error
        synchronize do
          @state.dead!
          callbacks.run_callbacks(:after_runner_died, error)
        end
      end
    end
  end
end
