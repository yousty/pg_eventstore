# frozen_string_literal: true

module PgEventstore
  module Extensions
    # Extension that implements creating of a subclass of the class it is used in. The point of creating a subclass is
    # to bound it to the specific connection. This way the specific connection will be available within tha class and
    # all its instances without affecting on the original class.
    # @!visibility private
    module UsingConnectionExtension
      def self.included(klass)
        klass.extend(ClassMethods)
      end

      module ClassMethods
        def connection
          raise("No connection was set. Are you trying to manipulate #{name} outside of its lifecycle?")
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
