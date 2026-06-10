# frozen_string_literal: true

module PgEventstore
  module EventsProcessorConsumer
    # @!visibility private
    class Single
      include EventsProcessorConsumer

      # @return [Float, Integer]
      EVENT_WAIT_TIMEOUT = 0.5

      class << self
        # @param handler [#call]
        # @param deserializer [PgEventstore::EventDeserializer]
        # @return [PgEventstore::EventsProcessorConsumer::Single]
        def create_consumer(handler, deserializer)
          raw_handler = ->(raw_event) { handler.call(deserializer.deserialize(raw_event)) }
          new(raw_handler)
        end
      end

      # @param handler [#call]
      def initialize(handler)
        @handler = handler
        @last_unprocessed_event = nil
      end

      # @return [void]
      def clear_unprocessed_events
        @last_unprocessed_event = nil
      end

      # @param callbacks [PgEventstore::Callbacks]
      # @param events_repository [PgEventstore::Chunks::Repository]
      # @param repository_cond [MonitorMixin::ConditionVariable]
      # @return [void]
      def call(callbacks, events_repository, repository_cond)
        raw_event =
          @last_unprocessed_event ||
          events_repository.wait_and_consume(
            entities_num: 1, timeout: EVENT_WAIT_TIMEOUT, condition: repository_cond
          ).first

        return if raw_event.nil?

        if raw_event.is_a?(Chunks::SubscriptionCheckpointChunk::Checkpoint)
          callbacks.run_callbacks(:checkpoint, raw_event.subscription_position)
          return
        end

        callbacks.run_callbacks(:process, raw_event.subscription_position) do
          @handler.call(raw_event.attributes)
        rescue => exception
          @last_unprocessed_event = raw_event
          raise Utils.wrap_exception(exception, global_position: raw_event.subscription_position)
        else
          clear_unprocessed_events
        end
      end
    end
  end
end
