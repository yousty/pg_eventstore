# frozen_string_literal: true

module PgEventstore
  class SubscriptionsLifecycle
    extend Forwardable

    # @return [Integer] number of seconds between heartbeat updates
    HEARTBEAT_INTERVAL = 10 # seconds

    # @!attribute runners
    #   @return [Array<PgEventstore::SubscriptionRunner>]
    attr_reader :runners

    # @param config_name [Symbol]
    # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
    def initialize(config_name, subscriptions_set_lifecycle, force_lock: false)
      @config_name = config_name
      @subscriptions_set_lifecycle = subscriptions_set_lifecycle
      @runners = []
      @subscriptions_pinged_at = Time.at(0)
      @force_lock = force_lock
    end

    # Locks all Subscriptions behind the current SubscriptionsSet
    # @return [void]
    def lock_all
      @runners.each do |runner|
        runner.lock!(@subscriptions_set_lifecycle.persisted_subscriptions_set.id, force: force_locked?)
      end
    rescue PgEventstore::SubscriptionAlreadyLockedError
      @subscriptions_set_lifecycle.reset_subscriptions_set
      raise
    end

    # @return [void]
    def ping_subscriptions
      return if @subscriptions_pinged_at > Time.now.utc - HEARTBEAT_INTERVAL

      runners = @runners.select do |runner|
        next false unless runner.running?

        runner.subscription.updated_at < Time.now.utc - HEARTBEAT_INTERVAL
      end
      unless runners.empty?
        Subscription.using_connection(@config_name).ping_all(
          @subscriptions_set_lifecycle.persisted_subscriptions_set.id, runners.map(&:subscription)
        )
      end

      @subscriptions_pinged_at = Time.now.utc
    end

    # @return [Array<PgEventstore::Subscription>]
    def subscriptions
      @runners.map(&:subscription)
    end

    # Sets the force_lock flag to true. If set - all related Subscriptions will ignore their lock state and will be
    # locked by the new SubscriptionsSet.
    # @return [void]
    def force_lock!
      message = <<~TEXT
        Usage of #force_lock! is deprecated and will be removed in v2. Please pass :force_lock keyword argument when \
        initializing SubscriptionsManager. Example: PgEventstore.subscriptions_manager(force_lock: true)
      TEXT
      Utils.deprecation_warning(message)
      @force_lock = true
    end

    # @return [Boolean]
    def force_locked?
      @force_lock
    end
  end
end
