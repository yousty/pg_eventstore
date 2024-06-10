# frozen_string_literal: true

module PgEventstore
  # This class actually processes events.
  # @!visibility private
  class EventsProcessor
    include Extensions::CallbacksExtension
    extend Forwardable

    def_delegators :@basic_runner, :state, :start, :stop, :wait_for_finish, :stop_async, :restore, :running?

    # @param handler [#call]
    def initialize(handler)
      @handler = handler
      @raw_events = []
      @basic_runner = BasicRunner.new(0, 5)
      attach_runner_callbacks
    end

    # @param raw_events [Array<Hash>]
    # @return [void]
    def feed(raw_events)
      raise EmptyChunkFedError.new("Empty chunk was fed!") if raw_events.empty?

      callbacks.run_callbacks(:feed, global_position(raw_events.last))
      @raw_events.push(*raw_events)
    end

    # Number of unprocessed events which are currently in a queue
    # @return [Integer]
    def events_left_in_chunk
      @raw_events.size
    end

    private

    # @param raw_event [Hash]
    # @return [void]
    def process_event(raw_event)
      callbacks.run_callbacks(:process, global_position(raw_event)) do
        @handler.call(raw_event)
      end
    end

    def attach_runner_callbacks
      @basic_runner.define_callback(:process_async, :before, method(:process_async))
      @basic_runner.define_callback(:after_runner_died, :before, method(:after_runner_died))
      @basic_runner.define_callback(:before_runner_restored, :before, method(:before_runner_restored))
      @basic_runner.define_callback(:change_state, :before, method(:change_state))
    end

    def process_async
      raw_event = @raw_events.shift
      return sleep 0.5 if raw_event.nil?

      process_event(raw_event)
    rescue
      @raw_events.unshift(raw_event)
      raise
    end

    def after_runner_died(...)
      callbacks.run_callbacks(:error, ...)
    end

    def before_runner_restored
      callbacks.run_callbacks(:restart)
    end

    def change_state(...)
      callbacks.run_callbacks(:change_state, ...)
    end

    # @param raw_event [Hash]
    # @return [Integer]
    def global_position(raw_event)
      raw_event['link'] ? raw_event['link']['global_position'] : raw_event['global_position']
    end
  end
end
