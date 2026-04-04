# frozen_string_literal: true

module PgEventstore
  module EventsProcessorConsumer
    # @!visibility private
    class Single
      include EventsProcessorConsumer

      class << self
        def create_consumer(handler, deserializer)
          raw_handler = ->(raw_event) { handler.call(deserializer.deserialize(raw_event)) }
          new(raw_handler)
        end
      end

      # @param handler [#call]
      def initialize(handler)
        @handler = handler
      end

      # @param callbacks [PgEventstore::Callbacks]
      # @param raw_events [PgEventstore::SynchronizedArray]
      # @param raw_events_cond [MonitorMixin::ConditionVariable]
      def call(callbacks, raw_events, raw_events_cond)
        raw_event = nil
        raw_events.synchronize do
          raw_events_cond.wait(0.5) if raw_events.empty?
          raw_event = raw_events.shift
        end
        return if raw_event.nil?

        callbacks.run_callbacks(:process, Utils.original_global_position(raw_event)) do
          @handler.call(raw_event)
        rescue => exception
          raw_events.unshift(raw_event)
          raise Utils.wrap_exception(exception, global_position: Utils.original_global_position(raw_event))
        end
      end
    end
  end
end
