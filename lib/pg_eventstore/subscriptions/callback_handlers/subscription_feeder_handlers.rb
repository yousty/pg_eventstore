# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionFeederHandlers
    include Extensions::CallbackHandlersExtension

    class << self
      # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
      # @param state [String]
      # @return [void]
      def update_subscriptions_set_state(subscriptions_set_lifecycle, state)
        subscriptions_set_lifecycle.persisted_subscriptions_set.update(state: state)
      end

      # @param subscriptions_lifecycle [PgEventstore::SubscriptionsLifecycle]
      # @return [void]
      def lock_subscriptions(subscriptions_lifecycle)
        subscriptions_lifecycle.lock_all
      end

      # @param subscriptions_lifecycle [PgEventstore::SubscriptionsLifecycle]
      # @return [void]
      def start_runners(subscriptions_lifecycle)
        subscriptions_lifecycle.runners.each(&:start)
      end

      # @param cmds_handler [PgEventstore::CommandsHandler]
      # @return [void]
      def start_cmds_handler(cmds_handler)
        cmds_handler.start
      end

      # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
      # @param error [StandardError]
      # @return [void]
      def persist_error_info(subscriptions_set_lifecycle, error)
        subscriptions_set_lifecycle.persisted_subscriptions_set.update(
          last_error: Utils.error_info(error), last_error_occurred_at: Time.now.utc
        )
      end

      # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
      # @return [void]
      def ping_subscriptions_set(subscriptions_set_lifecycle)
        subscriptions_set_lifecycle.ping_subscriptions_set
      end

      # @param subscriptions_lifecycle [PgEventstore::SubscriptionsLifecycle]
      # @param config_name [Symbol]
      # @return [void]
      def feed_runners(subscriptions_lifecycle, config_name)
        SubscriptionRunnersFeeder.new(config_name).feed(subscriptions_lifecycle.runners)
      end

      # @param subscriptions_lifecycle [PgEventstore::SubscriptionsLifecycle]
      # @return [void]
      def ping_subscriptions(subscriptions_lifecycle)
        subscriptions_lifecycle.ping_subscriptions
      end

      # @param subscriptions_lifecycle [PgEventstore::SubscriptionsLifecycle]
      # @return [void]
      def stop_runners(subscriptions_lifecycle)
        subscriptions_lifecycle.runners.each(&:stop_async).each(&:wait_for_finish)
      end

      # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
      # @return [void]
      def reset_subscriptions_set(subscriptions_set_lifecycle)
        subscriptions_set_lifecycle.reset_subscriptions_set
      end

      # @param cmds_handler [PgEventstore::CommandsHandler]
      # @return [void]
      def stop_commands_handler(cmds_handler)
        cmds_handler.stop
      end

      # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
      # @return [void]
      def update_subscriptions_set_restarts(subscriptions_set_lifecycle)
        subscriptions_set = subscriptions_set_lifecycle.persisted_subscriptions_set
        subscriptions_set.update(
          last_restarted_at: Time.now.utc, restart_count: subscriptions_set.restart_count + 1
        )
      end
    end
  end
end
