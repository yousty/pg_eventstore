# frozen_string_literal: true

module PgEventstore
  # Implements different states of a runner.
  # @!visibility private
  class RunnerState
    include Extensions::CallbacksExtension

    STATES = %i(initial running halting stopped dead).each_with_object({}) do |sym, result|
      result[sym] = sym.to_s.freeze
    end.freeze

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
      # @return [Symbol]
      define_method "#{state}!" do
        set_state(value)
      end
    end

    # @return [String] string representation of the state
    def to_s
      @state
    end

    private

    def set_state(state)
      old_state = @state
      @state = state
      callbacks.run_callbacks(:change_state, @state) unless old_state == @state
      @state
    end
  end
end
