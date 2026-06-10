# frozen_string_literal: true

module PgEventstore
  module EventsProcessorConsumer
    # @!visibility private
    class Multiple
      include EventsProcessorConsumer

      # @return [Float, Integer]
      EVENTS_WAIT_TIMEOUT = 0.5

      class << self
        # @param handler [#call]
        # @param deserializer [PgEventstore::EventDeserializer]
        # @return [PgEventstore::EventsProcessorConsumer::Multiple]
        def create_consumer(handler, deserializer)
          raw_handler = ->(raw_events) { handler.call(raw_events.map(&deserializer.method(:deserialize))) }
          new(raw_handler)
        end
      end

      # @param handler [#call]
      def initialize(handler)
        @handler = handler
        @last_unprocessed_events = nil
      end

      # @return [void]
      def clear_unprocessed_events
        @last_unprocessed_events = nil
      end

      # @param callbacks [PgEventstore::Callbacks]
      # @param events_repository [PgEventstore::Chunks::Repository]
      # @param repository_cond [MonitorMixin::ConditionVariable]
      # @return [void]
      def call(callbacks, events_repository, repository_cond)
        events_to_process =
          @last_unprocessed_events ||
          events_repository.wait_and_consume(
            entities_num: nil, timeout: EVENTS_WAIT_TIMEOUT, condition: repository_cond
          )
        return if events_to_process.empty?

        if events_to_process.first.is_a?(Chunks::SubscriptionCheckpointChunk::Checkpoint)
          callbacks.run_callbacks(:checkpoint, events_to_process.first.subscription_position)
          return
        end

        callbacks.run_callbacks(:process, events_to_process.last.subscription_position) do
          @handler.call(events_to_process.map(&:attributes))
        rescue => exception
          @last_unprocessed_events = events_to_process
          raise Utils.wrap_exception(
            exception, subscription_positions: events_to_process.map(&:subscription_position)
          )
        else
          clear_unprocessed_events
        end
      end
    end
  end
end
