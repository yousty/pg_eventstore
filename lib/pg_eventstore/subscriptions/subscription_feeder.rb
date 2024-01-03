# frozen_string_literal: true

module PgEventstore
  class SubscriptionFeeder
    extend Forwardable

    def_delegators :subscriptions_set, :id
    def_delegators :@basic_runner, :start, :stop, :restore

    # @param config_name [String]
    # @param set_name [String]
    def initialize(config_name, set_name)
      @config_name = config_name
      @runners = []
      @set_name = set_name
      @commands_handler = CommandsHandler.new(@config_name, self, @runners)
      @basic_runner = BasicRunner.new(1, 0)
      attach_runner_callbacks
    end

    def add(runner)
      assert_proper_state!
      @runners.push(runner)
    end

    # @return [void]
    def start_all
      return self unless @basic_runner.state.running?

      @runners.each(&:start)
      self
    end

    # @return [void]
    def stop_all
      return self unless @basic_runner.state.running?

      @runners.each(&:stop_async)
      self
    end

    private

    def lock_all
      @runners.each(&:persist).each { |runner| runner.lock!(subscriptions_set.id) }
    end

    def unlock_all
      @runners.each(&:unlock!)
    end

    # @return [PgEventstore::SubscriptionsSet]
    def subscriptions_set
      @subscription_set ||= SubscriptionsSet.using_connection(@config_name).create(name: @set_name)
    end

    # @return [PgEventstore::SubscriptionsFeeder]
    def subscription_feeder
      SubscriptionsFeeder.new(@config_name)
    end

    # @return [void]
    def attach_runner_callbacks
      @basic_runner.state.define_callback(:change_state, :after, method(:update_subscriptions_set_state))
      @basic_runner.define_callback(:before_runner_started, :before, method(:before_runner_started))
      @basic_runner.define_callback(:after_runner_died, :before, method(:after_runner_died))
      @basic_runner.define_callback(:process_async, :before, method(:process_async))
      @basic_runner.define_callback(:after_runner_stopped, :before, method(:after_runner_stopped))
    end

    def before_runner_started
      lock_all
      @commands_handler.start
      @runners.each(&:start)
    end

    def after_runner_died(error)
      subscriptions_set.update(last_error: Utils.error_info(error), last_error_occurred_at: Time.now.utc)
    end

    def process_async
      subscription_feeder.feed(@runners)
    end

    def after_runner_stopped
      @subscription_set&.delete
      @subscription_set = nil
      @runners.each(&:stop_async).each(&:wait_for_finish)
      unlock_all
      @commands_handler.stop
    end

    # @return [void]
    def update_subscriptions_set_state(state)
      subscriptions_set.update(state: state.to_s)
    end

    def assert_proper_state!
      return if @basic_runner.state.initial? || @basic_runner.state.stopped?

      error_message = <<~TEXT
        Could not add subscription - #{subscriptions_set.name}##{subscriptions_set.id} must be either in the initial \
        or in the stopped state, but it is in the #{@basic_runner.state} state now.
      TEXT
      raise error_message
    end
  end
end
