# frozen_string_literal: true

module PgEventstore
  class SubscriptionRunnerHandlers
    include Extensions::CallbackHandlersExtension

    class << self
      # @param stats [PgEventstore::SubscriptionHandlerPerformance]
      # @param action [Proc]
      # @param _current_position [Integer]
      # @return [void]
      def track_exec_time(stats, action, _current_position)
        stats.track_exec_time { action.call }
      end

      # @param subscription [PgEventstore::Subscription]
      # @param stats [PgEventstore::SubscriptionHandlerPerformance]
      # @param current_position [Integer]
      # @return [void]
      def update_subscription_stats(subscription, stats, current_position)
        subscription.update(
          average_event_processing_time: stats.average_event_processing_time,
          current_position: current_position,
          total_processed_events: subscription.total_processed_events + 1
        )
      end

      # @param subscription [PgEventstore::Subscription]
      # @param error [PgEventstore::WrappedException]
      # @return [void]
      def update_subscription_error(subscription, error)
        subscription.update(last_error: Utils.error_info(error), last_error_occurred_at: Time.now.utc)
      end

      # @param subscription [PgEventstore::Subscription]
      # @param global_position [Integer]
      # @return [void]
      def update_subscription_chunk_stats(subscription, global_position)
        subscription.update(last_chunk_fed_at: Time.now.utc, last_chunk_greatest_position: global_position)
      end

      # @param subscription [PgEventstore::Subscription]
      # @return [void]
      def update_subscription_restarts(subscription)
        subscription.update(last_restarted_at: Time.now.utc, restart_count: subscription.restart_count + 1)
      end

      # @param subscription [PgEventstore::Subscription]
      # @param state [String]
      # @return [void]
      def update_subscription_state(subscription, state)
        subscription.update(state: state)
      end
    end
  end
end
