# frozen_string_literal: true

module PgEventstore
  module CommandHandlers
    # @!visibility private
    class SubscriptionFeederCommands
      # @param config_name [Symbol]
      # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
      def initialize(config_name, subscription_feeder)
        @config_name = config_name
        @subscription_feeder = subscription_feeder
      end

      # Look up commands for the given SubscriptionFeeder and execute them
      # @return [void]
      def process
        commands.each do |command|
          command.exec_cmd(@subscription_feeder)
          queries.delete(command.id)
        end
      end

      private

      # @return [Array<PgEventstore::SubscriptionFeederCommands::Base>]
      def commands
        commands = queries.find_commands(@subscription_feeder.id)
        ping_cmd = commands.find do |cmd|
          cmd.name == 'Ping'
        end
        return commands unless ping_cmd

        # "Ping" command should go in prio
        [ping_cmd, *(commands - [ping_cmd])]
      end

      # @return [PgEventstore::SubscriptionsSetCommandQueries]
      def queries
        SubscriptionsSetCommandQueries.new(connection)
      end

      # @return [PgEventstore::Connection]
      def connection
        PgEventstore.connection(@config_name)
      end
    end
  end
end
