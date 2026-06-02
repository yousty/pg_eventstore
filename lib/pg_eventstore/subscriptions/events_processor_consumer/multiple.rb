# frozen_string_literal: true

module PgEventstore
  module EventsProcessorConsumer
    # @!visibility private
    class Multiple
      include EventsProcessorConsumer

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
          events_repository.wait_and_consume(entities_num: nil, timeout: 0.5, condition: repository_cond)
        return if events_to_process.empty?

        callbacks.run_callbacks(:process, Utils.original_global_position(events_to_process.last)) do
          @handler.call(events_to_process)
        rescue => exception
          @last_unprocessed_events = events_to_process
          raise Utils.wrap_exception(
            exception, global_positions: events_to_process.map(&Utils.method(:original_global_position))
          )
        else
          clear_unprocessed_events
        end
      end
    end
  end
end
