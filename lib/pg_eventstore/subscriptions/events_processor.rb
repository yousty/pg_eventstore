# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventsProcessor
    include Extensions::CallbacksExtension
    extend Forwardable

    FORCED_SHUTDOWN_DELAY = 60 # seconds

    attr_reader :state

    def_delegators :@lock, :synchronize

    def initialize(handler)
      @lock = Thread::Mutex.new
      @handler = handler
      @state = ObjectState.new
      @raw_events = []
    end

    # @param raw_events [Array<Hash>]
    # @return [void]
    def feed(raw_events)
      synchronize do
        callbacks.run_callbacks(:feed, raw_events.last&.dig('global_position'))
        @raw_events.push(*raw_events)
      end
    end

    def start
      synchronize { _start }
    end

    # @return [Integer]
    def events_left_in_chunk
      @raw_events.size
    end

    def stop
      synchronize do
        return self unless @state.running?

        @state.halting!
        Thread.new do
          stopping_at = Time.now.utc
          loop do
            # Give EventsProcessor up to FORCED_SHUTDOWN_DELAY seconds for graceful shutdown
            @runner&.exit if Time.now.utc - stopping_at > FORCED_SHUTDOWN_DELAY

            unless @runner&.alive?
              @state.stopped!
              @runner = nil
              break
            end
            sleep 0.1
          end
        end
        self
      end
    end

    # Use this method only if you want to restart dead runner. For all other cases please use #start/#stop
    def restore
      synchronize do
        return self unless @state.dead?

        @runner = nil
        _start
      end
    end
    has_callbacks :restart, :restore

    private

    def _start
      @runner ||= Thread.new do
        Thread.current.abort_on_exception = false
        Thread.current.report_on_exception = false
        @state.running!
        do_sleep = false
        loop do
          Thread.current.exit unless @state.running?
          sleep 0.5 if do_sleep
          synchronize do
            raw_event = @raw_events.shift
            do_sleep = raw_event.nil?
            next if do_sleep

            process_event(raw_event)
          end
        end
      rescue => e
        @state.dead!
        callbacks.run_callbacks(:error, e)
      end
    end

    def process_event(raw_event)
      callbacks.run_callbacks(:process, raw_event['global_position']) do
        @handler.call(raw_event)
      end
    end
  end
end
