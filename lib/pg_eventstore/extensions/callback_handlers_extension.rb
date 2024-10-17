# frozen_string_literal: true

module PgEventstore
  module Extensions
    module CallbackHandlersExtension
      def self.included(klass)
        klass.extend(ClassMethods)
      end

      module ClassMethods
        # @param name [Symbol] a name of the handler
        # @return [Proc]
        def setup_handler(name, *args)
          proc do |*rest|
            public_send(name, *args, *rest)
          end
        end
      end
    end
  end
end
