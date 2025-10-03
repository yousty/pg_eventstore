# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventsProcessorHandlers
    include Extensions::CallbackHandlersExtension

    class << self
      # @param callbacks [PgEventstore::Callbacks]
      # @param handler [#call]
      # @param raw_events [Array<Hash>]
      # @param raw_events_cond [MonitorMixin::ConditionVariable]
      # @return [void]
      def process_event(callbacks, handler, raw_events, raw_events_cond)
        raw_event = nil
        raw_events.synchronize do
          raw_events_cond.wait(0.5) if raw_events.empty?
          raw_event = raw_events.shift
        end
        return if raw_event.nil?

        callbacks.run_callbacks(:process, Utils.original_global_position(raw_event)) do
          handler.call(raw_event)
        rescue => exception
          raw_events.unshift(raw_event)
          raise Utils.wrap_exception(exception, global_position: Utils.original_global_position(raw_event))
        end
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
