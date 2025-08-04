# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionsSetLifecycle
    # @return [Integer] number of seconds between heartbeat updates
    HEARTBEAT_INTERVAL = 10 # seconds

    # @!attribute subscriptions_set
    #   @return [PgEventstore::SubscriptionsSet, nil]
    attr_reader :subscriptions_set

    # @param config_name [Symbol]
    # @param subscriptions_set_attrs [Hash]
    def initialize(config_name, subscriptions_set_attrs)
      @config_name = config_name
      @subscriptions_set_attrs = subscriptions_set_attrs
      @subscriptions_set_pinged_at = Time.at(0)
    end

    # @return [void]
    def ping_subscriptions_set
      return if @subscriptions_set_pinged_at > Time.now.utc - HEARTBEAT_INTERVAL

      persisted_subscriptions_set.update(updated_at: Time.now.utc)
      @subscriptions_set_pinged_at = Time.now.utc
    end

    # @return [PgEventstore::SubscriptionsSet]
    # rubocop:disable Naming/MemoizedInstanceVariableName
    def persisted_subscriptions_set
      @subscriptions_set ||= SubscriptionsSet.using_connection(@config_name).create(@subscriptions_set_attrs)
    end
    # rubocop:enable Naming/MemoizedInstanceVariableName

    # @return [void]
    def reset_subscriptions_set
      @subscriptions_set&.delete
      @subscriptions_set = nil
    end
  end
end
