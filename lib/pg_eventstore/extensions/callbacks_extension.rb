# frozen_string_literal: true

module PgEventstore
  module Extensions
    module CallbacksExtension
      def self.included(klass)
        klass.extend(ClassMethods)
        klass.prepend(InitCallbacks)
        klass.class_eval do
          attr_reader :callbacks
          private :callbacks
        end
      end

      def define_callback(...)
        callbacks.define_callback(...)
      end

      module InitCallbacks
        def initialize(...)
          @callbacks = Callbacks.new
          super
        end
      end

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
