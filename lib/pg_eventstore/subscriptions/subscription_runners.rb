# frozen_string_literal: true

module PgEventstore
  class SubscriptionRunners
    extend Forwardable

    attr_reader :state

    def_delegators :@lock, :synchronize

    # @param config_name [String]
    # @param set_name [String]
    def initialize(config_name, set_name)
      @config_name = config_name
      @runners = []
      @set_name = set_name
      @state = ObjectState.new
      @lock = Thread::Mutex.new
      attach_callbacks
    end

    def add(runner)
      @runners.push(runner)
    end

    # @return [void]
    def start_all
      synchronize do
        return self unless @state.initial? || @state.stopped?

        lock_all
        @runners.each(&:start)
        @state.running!
        start_feeder
      rescue => error
        @state.dead!
        subscriptions_set.update(last_error: Utils.error_info(error), last_error_occurred_at: Time.now.utc)
      end
      self
    end

    # @return [void]
    def stop_all
      synchronize do
        return self unless @state.running? || @state.dead?

        @feeder&.exit
        @feeder = nil
        @subscription_set&.delete
        @subscription_set = nil
        @runners.each(&:stop).each(&:wait_for_finish)
        unlock_all
        @state.stopped!
      end
      self
    end

    private

    def start_feeder
      @feeder ||= Thread.new do
        Thread.current.abort_on_exception = false
        Thread.current.report_on_exception = false

        loop do
          sleep 1

          subscription_feeder.feed(@runners)
        end
      rescue => error
        @state.dead!
        subscriptions_set.update(last_error: Utils.error_info(error), last_error_occurred_at: Time.now.utc)
      end
    end

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
    def attach_callbacks
      @state.define_callback(:change_state, :after, method(:update_subscriptions_set_state))
    end

    # @return [void]
    def update_subscriptions_set_state
      subscriptions_set.update(state: @state.to_s)
    end
  end
end
