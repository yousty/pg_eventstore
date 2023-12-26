# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class Subscription
    class << self
      def connection
        raise(<<~TEXT)
          No connection was set. Use PgEventstore::Subscription.using_connection(config_name) to create a class with \
          a connection of specific config.
        TEXT
      end

      # @param config_name [Symbol]
      # @return [Class<PgEventstore::Subscription>]
      def using_connection(config_name)
        Class.new(self).tap do |klass|
          klass.define_singleton_method(:connection) { PgEventstore.connection(config_name) }
          klass.class_eval do
            [:to_s, :inspect, :name].each do |m|
              define_singleton_method(m, &PgEventstore::Subscription.method(m))
            end
          end
        end
      end

      # @param set [String]
      # @param name [String]
      # @param options [Hash]
      # @param chunk_query_interval [Integer]
      # @param lock_id [String] UUIDv4 id of the set which reserves the subscription after itself
      # @return [PgEventstore::Subscription]
      def init_by(set:, name:, options:, chunk_query_interval:, lock_id:)
        new(**subscription_queries.find_or_create_by(set: set, name: name)).tap do |sub|
          sub.lock!(lock_id)
          sub.update(
            options: options,
            restarts_count: 0,
            last_restarted_at: nil,
            chunk_query_interval: chunk_query_interval,
            last_chunk_fed_at: Time.at(0),
            last_chunk_greatest_position: nil
          )
        end
      end

      private

      # @return [PgEventstore::SubscriptionQueries]
      def subscription_queries
        SubscriptionQueries.new(connection)
      end
    end

    include Extensions::OptionsExtension

    attribute(:id)
    attribute(:set)
    attribute(:name)
    attribute(:events_processed_total)
    attribute(:options) # Hash
    attribute(:current_position)
    attribute(:state)
    attribute(:events_processing_frequency)
    attribute(:restarts_count)
    attribute(:last_restarted_at)
    attribute(:last_error) # Hash
    attribute(:last_error_occurred_at)
    attribute(:chunk_query_interval) # Integer, seconds
    attribute(:last_chunk_fed_at)
    attribute(:last_chunk_greatest_position)
    attribute(:locked_by)
    attribute(:created_at)
    attribute(:updated_at)

    def options=(val)
      @options = Utils.deep_transform_keys(val, &:to_sym)
    end

    # @param attrs [Hash]
    # @return [self]
    def update(attrs)
      subscription_queries.update(self, attrs)
    end

    # @param attrs [Hash]
    # @return [Hash]
    def assign_attributes(attrs)
      attrs.each do |attr, value|
        public_send("#{attr}=", value)
      end
    end

    def lock!(lock_id)
      assign_attributes(subscription_queries.lock!(id, lock_id))
    end

    def unlock!
      assign_attributes(subscription_queries.unlock!(id, locked_by))
    end

    def reload
      attrs = subscription_queries.find_by(id: id)
      raise "Subscription #{id} does not exist any more!" unless attrs

      assign_attributes(attrs.transform_keys(&:to_s))
    end

    private

    def subscription_queries
      SubscriptionQueries.new(self.class.connection)
    end
  end
end
