# frozen_string_literal: true

class DummyErrorRecovery
  include PgEventstore::RunnerRecoveryStrategy

  def initialize(recoverable_message:, seconds_before_recovery: 0, mocked_action: nil)
    @seconds_before_recovery = seconds_before_recovery
    @mocked_action = mocked_action
    @recoverable_message = recoverable_message
  end

  def recovers?(error)
    PgEventstore::Utils.unwrap_exception(error).message == @recoverable_message
  end

  def recover(_error)
    @mocked_action&.run
    sleep @seconds_before_recovery
    true
  end
end
