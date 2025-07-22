# frozen_string_literal: true

module PgEventstore
  module CLI
    class TryToDeleteSubscriptionsSet
      class << self
        def try_to_delete(...)
          new(...).try_to_delete
        end
      end

      attr_reader :config_name, :subscriptions_set_id

      # @param config_name [Symbol]
      # @param subscriptions_set_id [Integer]
      def initialize(config_name, subscriptions_set_id)
        @config_name = config_name
        @subscriptions_set_id = subscriptions_set_id
      end

      # @return [Boolean] whether subscription was deleted
      def try_to_delete
        PgEventstore.logger&.info(
          "Trying to delete SubscriptionsSet##{subscriptions_set_id}."
        )
        cmd_name = SubscriptionFeederCommands.command_class('Ping').new.name
        subscriptions_set_commands_queries.find_or_create_by(
          subscriptions_set_id: subscriptions_set_id, command_name: cmd_name, data: {}
        )
        # Potentially CommandsHandler can be dead exactly at the same moment we expect it to process "Ping" command.
        # Wait for potential recover plus run interval and plus another second to allow potential processing of
        # "Ping" command. "Ping" command comes in prio, so it is guaranteed it will be processed as a first command.
        sleep RunnerRecoveryStrategies::RestoreConnection::TIME_BETWEEN_RETRIES + CommandsHandler::PULL_INTERVAL + 1
        if subscriptions_set_commands_queries.find_by(subscriptions_set_id: subscriptions_set_id, command_name: cmd_name)
          # "Ping" command wasn't consumed. Related process must be dead.
          subscriptions_set_queries.delete(subscriptions_set_id)
          PgEventstore.logger&.info(
            "SubscriptionsSet##{subscriptions_set_id} was deleted successfully. Proceeding with startup process."
          )
          return true
        end

        PgEventstore.logger&.warn(
          "Failed to delete SubscriptionsSet##{subscriptions_set_id}. It looks alive."
        )
        false
      rescue RecordNotFound
        # Failed to create "Ping" command because related SubscriptionsSet does not exist.
        true
      end

      private

      # @return [PgEventstore::SubscriptionsSetQueries]
      def subscriptions_set_queries
        SubscriptionsSetQueries.new(connection)
      end

      # @return [PgEventstore::SubscriptionsSetCommandQueries]
      def subscriptions_set_commands_queries
        SubscriptionsSetCommandQueries.new(connection)
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
