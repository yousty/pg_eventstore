# frozen_string_literal: true

module PgEventstore
  module RunnerRecoveryStrategies
    # @!visibility private
    class RestoreSubscriptionRunner
      include RunnerRecoveryStrategy

      # @param subscription [PgEventstore::Subscription]
      # @param restart_terminator [#call, nil]
      # @param failed_subscription_notifier [#call, nil]
      def initialize(subscription:, restart_terminator:, failed_subscription_notifier:)
        @subscription = subscription
        @restart_terminator = restart_terminator
        @failed_subscription_notifier = failed_subscription_notifier
      end

      def recovers?(error)
        error.is_a?(WrappedException)
      end

      def recover(error)
        return false if @restart_terminator&.call(@subscription.dup)

        if @subscription.restart_count >= @subscription.max_restarts_number
          @failed_subscription_notifier&.call(@subscription.dup, Utils.unwrap_exception(error))
          return false
        end

        sleep @subscription.time_between_restarts
        true
      end
    end
  end
end
