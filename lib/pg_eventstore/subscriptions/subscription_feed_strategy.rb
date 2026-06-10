# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  module SubscriptionFeedStrategy
    # @param runners [PgEventstore::SubscriptionRunner, Array<PgEventstore::SubscriptionRunner>]
    # @return [Array<PgEventstore::SubscriptionRunner>]
    def add(*runners)
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

    # @return [void]
    def feed
      raise NotImplementedError
    end
  end
end

require_relative 'subscription_feed_strategies/collection'
require_relative 'subscription_feed_strategies/index_read_strategy'
