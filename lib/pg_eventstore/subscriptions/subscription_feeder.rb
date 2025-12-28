# frozen_string_literal: true

module PgEventstore
  # This class is responsible for starting/stopping all SubscriptionRunners. The background runner of it is responsible
  # for events pulling and feeding those SubscriptionRunners.
  # @!visibility private
  class SubscriptionFeeder
    extend Forwardable

    # Determines how often to fetch events from the event store.
    # @see PgEventstore::Subscription::MIN_EVENTS_PULL_INTERVAL
    # @return [Float]
    EVENTS_PULL_INTERVAL = 0.2 # seconds
    private_constant :EVENTS_PULL_INTERVAL

    attr_reader :config_name

    def_delegators :@basic_runner, :start, :stop, :restore, :state, :wait_for_finish, :stop_async, :running?

    # @param config_name [Symbol]
    # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
    # @param subscriptions_lifecycle [PgEventstore::SubscriptionsLifecycle]
    def initialize(config_name:, subscriptions_set_lifecycle:, subscriptions_lifecycle:)
      @config_name = config_name
      @basic_runner = BasicRunner.new(
        run_interval: EVENTS_PULL_INTERVAL,
        async_shutdown_time: 0,
        recovery_strategies: recovery_strategies(config_name, subscriptions_set_lifecycle)
      )
      @subscriptions_set_lifecycle = subscriptions_set_lifecycle
      @subscriptions_lifecycle = subscriptions_lifecycle
      @commands_handler = CommandsHandler.new(@config_name, self, @subscriptions_lifecycle.runners)
      attach_runner_callbacks
    end

    # @return [Integer, nil]
    def id
      @subscriptions_set_lifecycle.subscriptions_set&.id
    end

    # Starts all SubscriptionRunners. This is only available if SubscriptionFeeder's runner is alive.
    # @return [void]
    def start_all
      return self unless @basic_runner.running?

      @subscriptions_lifecycle.runners.each(&:start)
      self
    end

    # Stops all SubscriptionRunners asynchronous. This is only available if SubscriptionFeeder's runner is alive.
    # @return [void]
    def stop_all
      return self unless @basic_runner.running?

      @subscriptions_lifecycle.runners.each(&:stop_async)
      self
    end

    private

    # @return [void]
    def attach_runner_callbacks
      @basic_runner.define_callback(
        :change_state, :after,
        SubscriptionFeederHandlers.setup_handler(:update_subscriptions_set_state, @subscriptions_set_lifecycle)
      )

      @basic_runner.define_callback(
        :before_runner_started, :before,
        SubscriptionFeederHandlers.setup_handler(:lock_subscriptions, @subscriptions_lifecycle)
      )
      @basic_runner.define_callback(
        :before_runner_started, :before,
        SubscriptionFeederHandlers.setup_handler(:start_runners, @subscriptions_lifecycle)
      )
      @basic_runner.define_callback(
        :before_runner_started, :before,
        SubscriptionFeederHandlers.setup_handler(:start_cmds_handler, @commands_handler)
      )

      @basic_runner.define_callback(
        :after_runner_died, :before,
        SubscriptionFeederHandlers.setup_handler(:persist_error_info, @subscriptions_set_lifecycle)
      )

      @basic_runner.define_callback(
        :process_async, :before,
        SubscriptionFeederHandlers.setup_handler(:ping_subscriptions_set, @subscriptions_set_lifecycle)
      )
      @basic_runner.define_callback(
        :process_async, :before,
        SubscriptionFeederHandlers.setup_handler(:feed_runners, @subscriptions_lifecycle, @config_name)
      )
      @basic_runner.define_callback(
        :process_async, :after,
        SubscriptionFeederHandlers.setup_handler(:ping_subscriptions, @subscriptions_lifecycle)
      )

      @basic_runner.define_callback(
        :after_runner_stopped, :before,
        SubscriptionFeederHandlers.setup_handler(:stop_runners, @subscriptions_lifecycle)
      )
      @basic_runner.define_callback(
        :after_runner_stopped, :before,
        SubscriptionFeederHandlers.setup_handler(:reset_subscriptions_set, @subscriptions_set_lifecycle)
      )
      @basic_runner.define_callback(
        :after_runner_stopped, :before,
        SubscriptionFeederHandlers.setup_handler(:stop_commands_handler, @commands_handler)
      )

      @basic_runner.define_callback(
        :before_runner_restored, :after,
        SubscriptionFeederHandlers.setup_handler(:update_subscriptions_set_restarts, @subscriptions_set_lifecycle)
      )
    end

    # @param config_name [Symbol]
    # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
    # @return [Array<PgEventstore::RunnerRecoveryStrategy>]
    def recovery_strategies(config_name, subscriptions_set_lifecycle)
      [
        RunnerRecoveryStrategies::RestoreConnection.new(config_name),
        RunnerRecoveryStrategies::RestoreSubscriptionFeeder.new(
          subscriptions_set_lifecycle:
        ),
      ]
    end
  end
end
