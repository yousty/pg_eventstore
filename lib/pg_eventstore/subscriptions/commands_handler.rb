# frozen_string_literal: true

require_relative 'command_handlers/subscription_feeder_commands'
require_relative 'command_handlers/subscription_runners_commands'

module PgEventstore
  # This class implements the runner which processes remote commands in the background. This allows you to remotely
  # control such actions as stop, start and restart of your Subscriptions.
  # @!visibility private
  class CommandsHandler
    extend Forwardable

    RESTART_DELAY = 5 # seconds
    PULL_INTERVAL = 1

    def_delegators :@basic_runner, :start, :stop, :state, :stop_async, :wait_for_finish

    # @param config_name [Symbol]
    # @param subscription_feeder [PgEventstore::SUbscriptionFeeder]
    # @param runners [Array<PgEventstore::SubscriptionRunner>]
    def initialize(config_name, subscription_feeder, runners)
      @config_name = config_name
      @subscription_feeder = subscription_feeder
      @runners = runners
      @basic_runner = BasicRunner.new(PULL_INTERVAL, 0)
      attach_runner_callbacks
    end

    private

    def attach_runner_callbacks
      @basic_runner.define_callback(:process_async, :before, method(:process_async))
      @basic_runner.define_callback(:after_runner_died, :before, method(:after_runner_died))
    end

    def process_async
      subscription_feeder_commands.process
      subscription_runners_commands.process
    end

    # @param error [StandardError]
    # @return [void]
    def after_runner_died(error)
      PgEventstore.logger&.error "#{self.class.name}: Error occurred: #{error.message}"
      PgEventstore.logger&.error "#{self.class.name}: Backtrace: #{error.backtrace&.join("\n")}"
      PgEventstore.logger&.error "#{self.class.name}: Trying to auto-repair in #{RESTART_DELAY} seconds..."
      Thread.new do
        sleep RESTART_DELAY
        @basic_runner.restore
      end
    end

    # @return [PgEventstore::CommandHandlers::SubscriptionFeederCommands]
    def subscription_feeder_commands
      CommandHandlers::SubscriptionFeederCommands.new(@config_name, @subscription_feeder)
    end

    # @return [PgEventstore::CommandHandlers::SubscriptionRunnersCommands]
    def subscription_runners_commands
      CommandHandlers::SubscriptionRunnersCommands.new(@config_name, @runners, @subscription_feeder.id)
    end
  end
end
