# frozen_string_literal: true

module PgEventstore
  # This class is responsible for starting/stopping all SubscriptionRunners. The background runner of it is responsible
  # for events pulling and feeding those SubscriptionRunners.
  class SubscriptionFeeder
    extend Forwardable

    def_delegators :@basic_runner, :start, :stop, :restore, :state, :wait_for_finish, :stop_async
    def_delegators :@subscriptions_lifecycle, :force_lock!

    # @param config_name [Symbol]
    # @param set_name [String]
    # @param max_retries [Integer] max number of retries of failed SubscriptionsSet
    # @param retries_interval [Integer] a delay between retries of failed SubscriptionsSet
    def initialize(config_name:, set_name:, max_retries:, retries_interval:)
      @config_name = config_name
      @commands_handler = CommandsHandler.new(@config_name, self, @runners)
      @basic_runner = BasicRunner.new(0.2, 0)
      @subscriptions_set_lifecycle = SubscriptionsSetLifecycle.new(
        @config_name,
        { name: set_name, max_restarts_number: max_retries, time_between_restarts: retries_interval }
      )
      @subscriptions_lifecycle = SubscriptionsLifecycle.new(@config_name, @subscriptions_set_lifecycle)
      attach_runner_callbacks
    end

    # @return [Integer]
    def id
      @subscriptions_set_lifecycle.persisted_subscriptions_set.id
    end

    # Adds SubscriptionRunner to the set
    # @param runner [PgEventstore::SubscriptionRunner]
    # @return [PgEventstore::SubscriptionRunner]
    def add(runner)
      assert_proper_state!
      @subscriptions_lifecycle.runners.push(runner)
      runner
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

    # Produces a copy of currently running Subscriptions. This is needed, because original Subscriptions objects are
    # dangerous to use - users may incidentally break their state.
    # @return [Array<PgEventstore::Subscription>]
    def read_only_subscriptions
      @subscriptions_lifecycle.subscriptions.map(&:dup)
    end

    # Produces a copy of current SubscriptionsSet. This is needed, because original SubscriptionsSet object is
    # dangerous to use - users may incidentally break its state.
    # @return [PgEventstore::SubscriptionsSet, nil]
    def read_only_subscriptions_set
      @subscriptions_set_lifecycle.subscriptions_set&.dup
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
        :after_runner_died, :before,
        SubscriptionFeederHandlers.setup_handler(:restart_runner, @subscriptions_set_lifecycle, @basic_runner)
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

    # This method helps to ensure that no Subscription is added after SubscriptionFeeder's runner is working
    # @return [void]
    # @raise [RuntimeError]
    def assert_proper_state!
      return if @basic_runner.initial? || @basic_runner.stopped?
      subscriptions_set = @subscriptions_set_lifecycle.persisted_subscriptions_set

      error_message = <<~TEXT
        Could not add subscription - #{subscriptions_set.name}##{subscriptions_set.id} must be \
        either in the initial or in the stopped state, but it is in the #{@basic_runner.state} state now.
      TEXT
      raise error_message
    end
  end
end
