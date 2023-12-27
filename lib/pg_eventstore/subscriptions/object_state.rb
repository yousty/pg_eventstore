# frozen_string_literal: true

module PgEventstore
  # Defines various states. It is used to set and get current object's state.
  # @!visibility private
  class ObjectState
    include Extensions::CallbacksExtension

    STATES = %i(initial running halting stopped dead).each_with_object({}) { |s, r| r[s] = s.to_s }.freeze

    def initialize
      initial!
    end

    STATES.each do |state, value|
      # Checks whether the object is in appropriate state
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
      @state = state
    end
    has_callbacks :change_state, :set_state
  end
end
