# frozen_string_literal: true

module PgEventstore
  # This class is responsible for starting/stopping all SubscriptionRunners. The background runner of it is responsible
  # for events pulling and feeding those SubscriptionRunners.
  class SubscriptionFeeder
    extend Forwardable

    HEARTBEAT_INTERVAL = 10 # seconds

    def_delegators :subscriptions_set, :id
    def_delegators :@basic_runner, :start, :stop, :restore, :state, :wait_for_finish, :stop_async

    # @param config_name [Symbol]
    # @param set_name [String]
    # @param max_retries [Integer] max number of retries of failed SubscriptionsSet
    # @param retries_interval [Integer] a delay between retries of failed SubscriptionsSet
    def initialize(config_name:, set_name:, max_retries:, retries_interval:)
      @config_name = config_name
      @runners = []
      @subscriptions_set_attrs = {
        name: set_name, max_restarts_number: max_retries, time_between_restarts: retries_interval
      }
      @commands_handler = CommandsHandler.new(@config_name, self, @runners)
      @basic_runner = BasicRunner.new(0.2, 0)
      @force_lock = false
      @subscriptions_pinged_at = Time.at(0)
      attach_runner_callbacks
    end

    # Adds SubscriptionRunner to the set
    # @param runner [PgEventstore::SubscriptionRunner]
    def add(runner)
      assert_proper_state!
      @runners.push(runner)
      runner
    end

    # Starts all SubscriptionRunners. This is only available if SubscriptionFeeder's runner is alive.
    # @return [void]
    def start_all
      return self unless @basic_runner.running?

      @runners.each(&:start)
      self
    end

    # Stops all SubscriptionRunners asynchronous. This is only available if SubscriptionFeeder's runner is alive.
    # @return [void]
    def stop_all
      return self unless @basic_runner.running?

      @runners.each(&:stop_async)
      self
    end

    # Sets the force_lock flash to true. If set - all related Subscriptions will ignore their lock state and will be
    # locked by the new SubscriptionsSet.
    def force_lock!
      @force_lock = true
    end

    # Produces a copy of currently running Subscriptions. This is needed, because original Subscriptions objects are
    # dangerous to use - users may incidentally break their state.
    # @return [Array<PgEventstore::Subscription>]
    def read_only_subscriptions
      @runners.map(&:subscription).map(&:dup)
    end

    # Produces a copy of current SubscriptionsSet. This is needed, because original SubscriptionsSet object is
    # dangerous to use - users may incidentally break its state.
    # @return [PgEventstore::SubscriptionsSet, nil]
    def read_only_subscriptions_set
      @subscriptions_set&.dup
    end

    private

    # Locks all Subscriptions behind the current SubscriptionsSet
    # @return [void]
    def lock_all
      @runners.each { |runner| runner.lock!(subscriptions_set.id, force: @force_lock) }
    end

    # @return [PgEventstore::SubscriptionsSet]
    def subscriptions_set
      @subscriptions_set ||= SubscriptionsSet.using_connection(@config_name).create(**@subscriptions_set_attrs)
    end

    # @return [PgEventstore::SubscriptionRunnersFeeder]
    def feeder
      SubscriptionRunnersFeeder.new(@config_name)
    end

    # @return [void]
    def attach_runner_callbacks
      @basic_runner.define_callback(:change_state, :after, method(:update_subscriptions_set_state))
      @basic_runner.define_callback(:before_runner_started, :before, method(:before_runner_started))
      @basic_runner.define_callback(:after_runner_died, :before, method(:after_runner_died))
      @basic_runner.define_callback(:after_runner_died, :after, method(:restart_runner))
      @basic_runner.define_callback(:process_async, :before, method(:ping_subscriptions_set))
      @basic_runner.define_callback(:process_async, :before, method(:process_async))
      @basic_runner.define_callback(:process_async, :after, method(:ping_subscriptions))
      @basic_runner.define_callback(:after_runner_stopped, :before, method(:after_runner_stopped))
      @basic_runner.define_callback(:before_runner_restored, :after, method(:update_runner_restarts))
    end

    # @return [void]
    def before_runner_started
      lock_all
      @runners.each(&:start)
      @commands_handler.start
    end

    # @param error [StandardError]
    # @return [void]
    def after_runner_died(error)
      subscriptions_set.update(last_error: Utils.error_info(error), last_error_occurred_at: Time.now.utc)
    end

    # @param _error [StandardError]
    # @return [void]
    def restart_runner(_error)
      return if subscriptions_set.restart_count >= subscriptions_set.max_restarts_number

      Thread.new do
        sleep subscriptions_set.time_between_restarts
        restore
      end
    end

    # @return [void]
    def update_runner_restarts
      subscriptions_set.update(last_restarted_at: Time.now.utc, restart_count: subscriptions_set.restart_count + 1)
    end

    # @return [void]
    def process_async
      feeder.feed(@runners)
    end

    # @return [void]
    def ping_subscriptions_set
      return if subscriptions_set.updated_at > Time.now.utc - HEARTBEAT_INTERVAL

      subscriptions_set.update(updated_at: Time.now.utc)
    end

    # @return [void]
    def ping_subscriptions
      return if @subscriptions_pinged_at > Time.now.utc - HEARTBEAT_INTERVAL

      runners = @runners.select do |runner|
        next false unless runner.running?

        runner.subscription.updated_at < Time.now.utc - HEARTBEAT_INTERVAL
      end
      unless runners.empty?
        Subscription.using_connection(@config_name).ping_all(subscriptions_set.id, runners.map(&:subscription))
      end

      @subscriptions_pinged_at = Time.now.utc
    end

    # @return [void]
    def after_runner_stopped
      @runners.each(&:stop_async).each(&:wait_for_finish)
      @subscriptions_set&.delete
      @subscriptions_set = nil
      @commands_handler.stop
    end

    # @return [void]
    def update_subscriptions_set_state(state)
      subscriptions_set.update(state: state)
    end

    # This method helps to ensure that no Subscription is added after SubscriptionFeeder's runner is working
    # @return [void]
    # @raise [RuntimeError]
    def assert_proper_state!
      return if @basic_runner.initial? || @basic_runner.stopped?

      error_message = <<~TEXT
        Could not add subscription - #{subscriptions_set.name}##{subscriptions_set.id} must be either in the initial \
        or in the stopped state, but it is in the #{@basic_runner.state} state now.
      TEXT
      raise error_message
    end
  end
end
