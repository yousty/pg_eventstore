# frozen_string_literal: true

module PgEventstore
  module Extensions
    module UsingConnectionExtension
      def self.included(klass)
        klass.extend(ClassMethods)
      end

      module ClassMethods
        def connection
          raise(<<~TEXT)
            No connection was set. Use PgEventstore::Subscription.using_connection(config_name) to create a class with \
            a connection of specific config.
          TEXT
        end

        # @param config_name [Symbol]
        # @return [Class<PgEventstore::Subscription>]
        def using_connection(config_name)
          original_class = self
          Class.new(original_class).tap do |klass|
            klass.define_singleton_method(:connection) { PgEventstore.connection(config_name) }
            klass.class_eval do
              [:to_s, :inspect, :name].each do |m|
                define_singleton_method(m, &original_class.method(m))
              end
            end
          end
        end
      end
    end
  end
end
