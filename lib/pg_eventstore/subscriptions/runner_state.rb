# frozen_string_literal: true

module PgEventstore
  # Implements different states of a runner.
  # @!visibility private
  class RunnerState
    include Extensions::CallbacksExtension

    # @return [Hash<Symbol => String>]
    STATES = %i(initial running halting stopped dead).to_h { [_1, _1.to_s.freeze] }.freeze

    def initialize
      initial!
    end

    STATES.each do |state, value|
      # Checks whether a runner is in appropriate state
      # @return [Boolean]
      define_method "#{state}?" do
        @state == value
      end

      # Sets the state.
      # @return [String]
      define_method "#{state}!" do
        set_state(value)
      end
    end

    # @return [String] string representation of the state
    def to_s
      @state
    end

    private

    # @param state [String]
    # @return [String]
    def set_state(state)
      old_state = @state
      @state = state
      callbacks.run_callbacks(:change_state, @state) unless old_state == @state
      @state
    end
  end
end
