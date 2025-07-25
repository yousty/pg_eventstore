# frozen_string_literal: true

module PgEventstore
  # Defines an interface of a recovery strategy of the BasicRunner.
  # See {PgEventstore::BasicRunner} for an example of usage.
  module RunnerRecoveryStrategy
    # Determines whether this strategy can recover from the error. If multiple strategies can recover from the error,
    # the first one from the :recovery_strategies array is selected.
    # @param error [StandardError]
    # @return [Boolean]
    def recovers?(error)
    end

    # Actual implementation of recovery strategy. Usually you want to implement here a logic that restores from the
    # error. The returned boolean value will be used to determine whether the runner should be restarted.
    # @param error [StandardError]
    # @return [Boolean]
    def recover(error)
    end
  end
end
