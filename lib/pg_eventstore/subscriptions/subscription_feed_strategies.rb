# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategies
    # @param runner [PgEventstore::SubscriptionRunner]
    # @return [Array<PgEventstore::SubscriptionRunner>]
    def add(runner)
      raise NotImplementedError
    end

    # @return [Integer]
    def size
      raise NotImplementedError
    end

    # @return [Boolean]
    def any?
      raise NotImplementedError
    end

    # @param safe_position [Integer]
    # @return [void]
    def feed(safe_position)
      raise NotImplementedError
    end
  end
end

require_relative 'subscription_feed_strategies/affected_partitions_size_map'
require_relative 'subscription_feed_strategies/collection'
require_relative 'subscription_feed_strategies/direct_read'
require_relative 'subscription_feed_strategies/index_read'
