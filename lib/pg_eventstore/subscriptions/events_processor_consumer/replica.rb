# frozen_string_literal: true

module PgEventstore
  module EventsProcessorConsumer
    # @!visibility private
    class Replica
      include EventsProcessorConsumer

      # @return [Float, Integer]
      EVENTS_WAIT_TIMEOUT = 0.5

      class << self
        # @param config_name [Symbol]
        # @param replica_config_name [Symbol]
        # @return [PgEventstore::EventsProcessorConsumer::Replica]
        def create_consumer(config_name, replica_config_name)
          handler = ReplicaSubscriptionHandler.new(config_name, replica_config_name)
          raw_handler = ->(events) { handler.call(events) }
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

        callbacks.run_callbacks(:process, events_to_process.last.subscription_position, events_to_process.size) do
          @handler.call(events_to_process)
        rescue => exception
          @last_unprocessed_events = events_to_process
          raise Utils.wrap_exception(
            exception,
            subscription_position_range: [
              events_to_process.first.subscription_position,
              events_to_process.last.subscription_position,
            ]
          )
        else
          clear_unprocessed_events
        end
      end
    end
  end
end
