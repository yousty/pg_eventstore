# frozen_string_literal: true

module PgEventstore
  class EventsProcessorHandlers
    include Extensions::CallbackHandlersExtension

    class << self
      # @param callbacks [PgEventstore::Callbacks]
      # @param handler [#call]
      # @param raw_events [Array<Hash>]
      # @return [void]
      def process_event(callbacks, handler, raw_events)
        raw_event = raw_events.shift
        return sleep 0.5 if raw_event.nil?

        callbacks.run_callbacks(:process, Utils.original_global_position(raw_event)) do
          handler.call(raw_event)
        end
      rescue => exception
        raw_events.unshift(raw_event)
        raise Utils.wrap_exception(exception, global_position: Utils.original_global_position(raw_event))
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
