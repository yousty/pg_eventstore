# frozen_string_literal: true

module PgEventstore
  # Allows you to define before, around and after callbacks withing the certain action. It is especially useful during
  # asynchronous programming when you need to be able to react on asynchronous actions from the outside.
  # Example:
  #   class MyAwesomeClass
  #     attr_reader :callbacks
  #
  #     def initialize
  #       @callbacks = PgEventstore::Callbacks.new
  #     end
  #
  #     def do_something
  #       Thread.new do
  #         @callbacks.run_callbacks(:something_happened) do
  #           puts "I did something useful!"
  #         end
  #       end
  #     end
  #
  #     def do_something_else
  #       @callbacks.run_callbacks(:something_else_happened, :foo, bar: :baz) do
  #         puts "Something else happened!"
  #       end
  #     end
  #   end
  #
  #   obj = MyAwesomeClass.new
  #   obj.callbacks.define_callback(:something_happened, :before, proc { puts "In before callback" })
  #   obj.callbacks.define_callback(:something_happened, :after, proc { puts "In after callback" })
  #   obj.callbacks.define_callback(
  #     :something_happened, :around,
  #     proc { |action| puts "In around before action"; action.call; puts "In around after action" }
  #   )
  #   obj.do_something
  # Outputs:
  #   In before callback
  #   In around callback before action
  #   I did something useful!
  #   In around callback after action
  #   In after callback
  # Please note, that it is important to call *action.call* in around callback. Otherwise action simply won't be called.
  #
  # Optionally you can provide any set of arguments to {#run_callbacks} method. They will be passed to your callbacks
  # functions then. Example:
  #
  #   obj = MyAwesomeClass.new
  #   obj.callbacks.define_callback(
  #     :something_else_happened, :before,
  #     proc { |*args, **kwargs| puts "In before callback. Args: #{args}, kwargs: #{kwargs}." }
  #   )
  #   obj.callbacks.define_callback(
  #     :something_else_happened, :after,
  #     proc { |*args, **kwargs| puts "In after callback. Args: #{args}, kwargs: #{kwargs}." }
  #   )
  #   obj.callbacks.define_callback(
  #     :something_else_happened, :around,
  #     proc { |action, *args, **kwargs|
  #       puts "In around before action. Args: #{args}, kwargs: #{kwargs}."
  #       action.call
  #       puts "In around after action. Args: #{args}, kwargs: #{kwargs}."
  #     }
  #   )
  #   obj.do_something_else
  # Outputs:
  #   In before callback. Args: [:foo], kwargs: {:bar=>:baz}.
  #   In around before action. Args: [:foo], kwargs: {:bar=>:baz}.
  #   I did something useful!
  #   In around after action. Args: [:foo], kwargs: {:bar=>:baz}.
  #   In after callback. Args: [:foo], kwargs: {:bar=>:baz}.
  class Callbacks
    def initialize
      @callbacks = {}
    end

    # @param action [Object] an object, that represents your action. In most cases you want to use a symbol there
    # @param filter [Symbol] callback filter. Supported values are :before, :after and :around
    # @param callback [#call]
    # @return [void]
    def define_callback(action, filter, callback)
      @callbacks[action] ||= {}
      @callbacks[action][filter] ||= []
      @callbacks[action][filter].push(callback)
    end

    # @param action [Object] an action to run
    # @return [Object] the result of passed block
    def run_callbacks(action, *args, **kwargs, &blk)
      return (yield if block_given?) unless @callbacks[action]

      run_before_callbacks(action, *args, **kwargs)
      result = run_around_callbacks(action, *args, **kwargs, &blk)
      run_after_callbacks(action, *args, **kwargs)
      result
    end

    # @param action [Object]
    # @param filter [Symbol]
    # @param callback [#call]
    # @return [void]
    def remove_callback(action, filter, callback)
      return unless @callbacks.dig(action, filter)

      @callbacks[action][filter].delete(callback)
    end

    # Clear all defined callbacks
    # @return [void]
    def clear
      @callbacks.clear
    end

    private

    # @return [void]
    def run_before_callbacks(action, *args, **kwargs)
      @callbacks[action][:before]&.each do |callback|
        callback.call(*args, **kwargs)
      end
    end

    # @return [Object] the result of the passed block
    def run_around_callbacks(action, *args, **kwargs, &blk)
      result = nil
      stack = [proc { result = yield if block_given? }]
      @callbacks[action][:around]&.reverse_each&.with_index do |callback, index|
        stack.push(proc { callback.call(stack[index], *args, **kwargs); result })
      end
      stack.last.call(*args, **kwargs)
      result
    end

    # @return [void]
    def run_after_callbacks(action, *args, **kwargs)
      @callbacks[action][:after]&.each do |callback|
        callback.call(*args, **kwargs)
      end
    end
  end
end
