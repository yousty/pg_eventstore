# frozen_string_literal: true

module PgEventstore
  module Extensions
    # Integrates PgEventstore::Calbacks into your object. Example usage:
    #   class MyAwesomeClass
    #     include CallbacksExtension
    #   end
    # Now you have {#define_callback} public method to define callbacks outside your class' object, and you can use
    # _#callbacks_ private method to run callbacks inside your class' object. You can also use _.has_callbacks_
    # public class method to wrap the desired method into {Callbacks#run_callbacks}. Example:
    #   class MyAwesomeClass
    #     include PgEventstore::Extensions::CallbacksExtension
    #
    #     def initialize(foo)
    #       @foo = foo
    #     end
    #
    #     def do_something
    #       puts "I did something useful: #{@foo.inspect}!"
    #     end
    #     has_callbacks :something_happened, :do_something
    #
    #     def do_something_else
    #       callbacks.run_callbacks(:something_else_happened) do
    #         puts "I did something else!"
    #       end
    #     end
    #   end
    #
    #   obj = MyAwesomeClass.new(:foo)
    #   obj.define_callback(
    #     :something_happened, :before, proc { puts "In before callback of :something_happened." }
    #   )
    #   obj.define_callback(
    #     :something_else_happened, :before, proc { puts "In before callback of :something_else_happened." }
    #   )
    #   obj.do_something
    #   obj.do_something_else
    # Outputs:
    #   In before callback of :something_happened.
    #   I did something useful: :foo!
    #   In before callback of :something_else_happened.
    #   I did something else!
    module CallbacksExtension
      def self.included(klass)
        klass.extend(ClassMethods)
        klass.prepend(InitCallbacks)
        klass.class_eval do
          attr_reader :callbacks
          private :callbacks
        end
      end

      # @return [void]
      def define_callback(...)
        callbacks.define_callback(...)
      end

      # @!visibility private
      module InitCallbacks
        def initialize(...)
          @callbacks = Callbacks.new
          super
        end
      end

      # @!visibility private
      module ClassMethods
        # Wraps method with Callbacks#run_callbacks. This allows you to define callbacks by the given action
        # @param action [String, Symbol]
        # @param method_name [Symbol]
        # @return [void]
        def has_callbacks(action, method_name)
          visibility_method = visibility_method(method_name)
          m = Module.new do
            define_method(method_name) do |*args, **kwargs, &blk|
              callbacks.run_callbacks(action) { super(*args, **kwargs, &blk) }
            end
            send visibility_method, method_name
          end
          prepend m
        end

        private

        def visibility_method(method_name)
          return :public if public_method_defined?(method_name)
          return :protected if protected_method_defined?(method_name)

          :private
        end
      end
    end
  end
end
