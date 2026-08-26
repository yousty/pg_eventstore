# frozen_string_literal: true

module PgEventstore
  module RunnerRecoveryStrategies
    # Reports a subscription death that no other strategy handles, then leaves it dead.
    #
    # Strategies are matched in order and the first match wins, so this one only ever sees errors
    # {RestoreConnection} and {RestoreSubscriptionRunner} both declined. It exists because such a
    # death is otherwise completely silent:
    #
    # * `BasicRunner#recoverable` calls `async_recover` only when a strategy matched the error, and
    # * `failed_subscription_notifier` is invoked from inside {RestoreSubscriptionRunner},
    #
    # so an error no strategy recognises marks the runner dead without ever reaching the notifier.
    # Nothing is written to `Subscription#last_error` on that path either, which leaves no trace of
    # the death in the database or in the host application's error tracker.
    # @!visibility private
    class ReportUnrecoverableError
      include RunnerRecoveryStrategy

      # @param subscription [PgEventstore::Subscription]
      # @param failed_subscription_notifier [#call, nil]
      def initialize(subscription:, failed_subscription_notifier:)
        @subscription = subscription
        @failed_subscription_notifier = failed_subscription_notifier
      end

      # Matches every error on purpose. Registering this strategy last is what makes that safe: an
      # error reaching it has already been declined by every strategy that could recover from it.
      # @param _error [StandardError]
      # @return [true]
      def recovers?(_error)
        true
      end

      # @param error [StandardError]
      # @return [false] the subscription stays dead - this strategy reports, it does not recover
      def recover(error)
        @failed_subscription_notifier&.call(@subscription.dup, Utils.unwrap_exception(error))
        false
      end
    end
  end
end
