# frozen_string_literal: true

require_relative 'command_handlers/subscription_feeder_commands'
require_relative 'command_handlers/subscription_runners_commands'

module PgEventstore
  class CommandsHandler
    extend Forwardable

    def_delegators :@basic_runner, :start, :stop

    def initialize(config_name, subscription_feeder, runners)
      @config_name = config_name
      @subscription_feeder = subscription_feeder
      @runners = runners
      @basic_runner = BasicRunner.new(1, 0)
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

    def after_runner_died(error)
      PgEventstore.logger&.error "#{self.class.name}: Error occurred: #{error.message}"
      PgEventstore.logger&.error "#{self.class.name}: Backtrace: #{error.backtrace&.join("\n")}"
      PgEventstore.logger&.error "#{self.class.name}: Trying to auto-repair in 5 seconds..."
      Thread.new do
        sleep 5
        @basic_runner.restore
      end
    end

    def subscription_feeder_commands
      CommandHandlers::SubscriptionFeederCommands.new(@config_name, @subscription_feeder)
    end

    def subscription_runners_commands
      CommandHandlers::SubscriptionRunnersCommands.new(@config_name, @runners)
    end
  end
end
