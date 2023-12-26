# frozen_string_literal: true

module PgEventstore
  class Callbacks
    def initialize
      @callbacks = {}
    end

    # @param action [Object] an object, that represents your action. In most cases you want to use a symbol there
    # @param filter [Symbol] callback filter. Supported values are :before, :after and :around
    # @return [void]
    def define_callback(action, filter, callback)
      @callbacks[action] ||= {}
      @callbacks[action][filter] ||= []
      @callbacks[action][filter].push(callback)
    end

    # @param action [Object] an action to run
    # @return [Object] result of your action
    def run_callbacks(action, ...)
      return yield unless @callbacks[action]

      result = nil

      @callbacks[action][:before]&.each do |callback|
        callback.call(...)
      end

      stack = [proc { result = yield if block_given? }]
      @callbacks[action][:around]&.each&.with_index do |callback, index|
        stack.push(proc { callback.call(stack[index], ...); result })
      end
      stack.last.call(...)

      @callbacks[action][:after]&.each do |callback|
        callback.call(...)
      end
      result
    end
  end
end
