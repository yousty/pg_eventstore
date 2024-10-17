# frozen_string_literal: true

module PgEventstore
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

      # @param basic_runner [PgEventstore::BasicRunner]
      # @param restart_delay [Integer]
      # @param error [StandardError]
      # @return [void]
      def restore_runner(basic_runner, restart_delay, error)
        PgEventstore.logger&.error "PgEventstore::CommandsHandler: Error occurred: #{error.message}"
        PgEventstore.logger&.error "PgEventstore::CommandsHandler: Backtrace: #{error.backtrace&.join("\n")}"
        PgEventstore.logger&.error "PgEventstore::CommandsHandler: Trying to auto-repair in #{restart_delay} seconds..."
        Thread.new do
          sleep restart_delay
          basic_runner.restore
        end
      end
    end
  end
end
