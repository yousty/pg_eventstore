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
        @last_unprocessed_event = nil
      end

      def clear_unprocessed_events
        @last_unprocessed_event = nil
      end

      # @param callbacks [PgEventstore::Callbacks]
      # @param events_repository [PgEventstore::RawEntities::EventsRepository]
      # @param repository_cond [MonitorMixin::ConditionVariable]
      def call(callbacks, events_repository, repository_cond)
        raw_event =
          @last_unprocessed_event ||
          events_repository.wait_and_consume(events_num: 1, timeout: 0.5, condition: repository_cond).first
        return if raw_event.nil?

        callbacks.run_callbacks(:process, Utils.original_global_position(raw_event)) do
          @handler.call(raw_event)
        rescue => exception
          @last_unprocessed_event = raw_event
          raise Utils.wrap_exception(exception, global_position: Utils.original_global_position(raw_event))
        else
          clear_unprocessed_events
        end
      end
    end
  end
end
