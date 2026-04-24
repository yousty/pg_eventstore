# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventsProcessorHandlers
    include Extensions::CallbackHandlersExtension

    class << self
      # @param consumer [PgEventstore::EventsProcessorConsumer]
      # @param callbacks [PgEventstore::Callbacks]
      # @param events_repository [PgEventstore::RawEntities::EventsRepository]
      # @param repository_cond [MonitorMixin::ConditionVariable]
      # @return [void]
      def consume_events(consumer, callbacks, events_repository, repository_cond)
        consumer.call(callbacks, events_repository, repository_cond)
      end

      # @param callbacks [PgEventstore::Callbacks]
      # @param error [StandardError]
      # @return [void]
      def after_runner_died(callbacks, error)
        callbacks.run_callbacks(:error, error)
      end

      # @param callbacks [PgEventstore::Callbacks]
      # @return [void]
      def before_runner_restored(callbacks)
        callbacks.run_callbacks(:restart)
      end

      # @param callbacks [PgEventstore::Callbacks]
      # @param state [String]
      # @return [void]
      def change_state(callbacks, state)
        callbacks.run_callbacks(:change_state, state)
      end
    end
  end
end
