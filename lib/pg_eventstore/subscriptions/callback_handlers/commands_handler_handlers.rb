# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class CommandsHandlerHandlers
    include Extensions::CallbackHandlersExtension

    class << self
      # @param config_name [Symbol]
      # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
      # @return [void]
      def process_feeder_commands(config_name, subscription_feeder)
        CommandHandlers::SubscriptionFeederCommands.new(config_name, subscription_feeder).process
      end

      # @param config_name [Symbol]
      # @param runners [Array<PgEventstore::SubscriptionRunner>]
      # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
      # @return [void]
      def process_runners_commands(config_name, runners, subscription_feeder)
        CommandHandlers::SubscriptionRunnersCommands.new(config_name, runners, subscription_feeder.id).process
      end
    end
  end
end
