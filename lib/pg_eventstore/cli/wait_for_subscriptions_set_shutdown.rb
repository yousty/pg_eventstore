# frozen_string_literal: true

module PgEventstore
  module CLI
    # @!visibility private
    class WaitForSubscriptionsSetShutdown
      class << self
        def wait_for_shutdown(...)
          new(...).wait_for_shutdown
        end
      end

      # @return [Float] seconds
      SHUTDOWN_CHECK_INTERVAL = 2.0

      attr_reader :config_name, :subscriptions_set_id

      # @param config_name [Symbol]
      # @param subscriptions_set_id [Integer]
      def initialize(config_name, subscriptions_set_id)
        @config_name = config_name
        @subscriptions_set_id = subscriptions_set_id
      end

      # @return [Boolean]
      def wait_for_shutdown
        PgEventstore.logger&.info(
          "Trying to wait for shutdown of SubscriptionsSet##{subscriptions_set_id}."
        )
        deadline = Time.now.utc + config.subscription_graceful_shutdown_timeout
        loop do
          find_set!
          return false if Time.now.utc > deadline

          sleep SHUTDOWN_CHECK_INTERVAL
        end
      rescue RecordNotFound
        PgEventstore.logger&.warn(
          "SubscriptionsSet##{subscriptions_set_id} no longer exists. Proceeding with startup process."
        )
        true
      end

      private

      # @return [PgEventstore::SubscriptionsSetQueries]
      def subscriptions_set_queries
        SubscriptionsSetQueries.new(connection)
      end

      # @return [PgEventstore::SubscriptionsSet]
      # @raise [PgEventstore::RecordNotFound]
      def find_set!
        SubscriptionsSet.using_connection(config_name).new(**subscriptions_set_queries.find!(subscriptions_set_id))
      end

      # @return [PgEventstore::Connection]
      def connection
        PgEventstore.connection(config_name)
      end

      # @return [PgEventstore::Config]
      def config
        PgEventstore.config(config_name)
      end
    end
  end
end
