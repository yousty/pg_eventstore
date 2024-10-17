# frozen_string_literal: true

require_relative 'command_handlers/subscription_feeder_commands'
require_relative 'command_handlers/subscription_runners_commands'

module PgEventstore
  # This class implements the runner which processes remote commands in the background. This allows you to remotely
  # control such actions as stop, start and restart of your Subscriptions.
  # @!visibility private
  class CommandsHandler
    extend Forwardable

    # @return [Integer] the delay in seconds between runner restarts
    RESTART_DELAY = 5
    # @return [Integer] seconds, how often to check for new commands
    PULL_INTERVAL = 1

    def_delegators :@basic_runner, :start, :stop, :state, :stop_async, :wait_for_finish

    # @param config_name [Symbol]
    # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
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
      @basic_runner.define_callback(
        :process_async, :before,
      CommandsHandlerHandlers.setup_handler(:process_feeder_commands, @config_name, @subscription_feeder)
      )
      @basic_runner.define_callback(
        :process_async, :before,
        CommandsHandlerHandlers.setup_handler(:process_runners_commands, @config_name, @runners, @subscription_feeder)
      )

      @basic_runner.define_callback(
        :after_runner_died, :before,
        CommandsHandlerHandlers.setup_handler(:restore_runner, @basic_runner, RESTART_DELAY)
      )
    end
  end
end
