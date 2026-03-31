# frozen_string_literal: true

module PgEventstore
  module EventsProcessorConsumer
    # @!visibility private
    class Multiple
      include EventsProcessorConsumer

      class << self
        def create_consumer(handler, deserializer)
          raw_handler = ->(raw_events) { handler.call(raw_events.map(&deserializer.method(:deserialize))) }
          new(raw_handler)
        end
      end

      # @param handler [#call]
      def initialize(handler)
        @handler = handler
      end

      # @param callbacks [PgEventstore::Callbacks]
      # @param raw_events [Array<Hash>]
      # @param raw_events_cond [MonitorMixin::ConditionVariable]
      def call(callbacks, raw_events, raw_events_cond)
        events_to_process = []
        raw_events.synchronize do
          raw_events_cond.wait(0.5) if raw_events.empty?
          events_to_process = raw_events.slice!(0..)
        end
        return if events_to_process.empty?

        callbacks.run_callbacks(:process, Utils.original_global_position(events_to_process.last)) do
          @handler.call(events_to_process)
        rescue => exception
          raw_events.unshift(*events_to_process)
          raise Utils.wrap_exception(
            exception, global_positions: events_to_process.map(&Utils.method(:original_global_position))
          )
        end
      end
    end
  end
end
