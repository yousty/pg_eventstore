# frozen_string_literal: true

module PgEventstore
  module RunnerRecoveryStrategies
    # Reports a subscription death that no other strategy handles, then leaves it dead.
    # @!visibility private
    class ReportSubscriptionUnrecoverableError
      include RunnerRecoveryStrategy

      # @param subscription [PgEventstore::Subscription]
      # @param failed_subscription_notifier [#call, nil]
      def initialize(subscription:, failed_subscription_notifier:)
        @subscription = subscription
        @failed_subscription_notifier = failed_subscription_notifier
      end

      # @param _error [StandardError]
      # @return [true]
      def recovers?(_error)
        true
      end

      # @param error [StandardError]
      # @return [false] the subscription stays dead - this strategy reports, it does not recover
      def recover(error)
        @failed_subscription_notifier&.call(@subscription.dup, error)
        false
      end
    end
  end
end
