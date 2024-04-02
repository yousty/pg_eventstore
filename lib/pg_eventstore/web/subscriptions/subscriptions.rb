# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      class Subscriptions
        # @param config [Symbol]
        # @param current_set [String]
        def initialize(config, current_set)
          @config = config
          @current_set = current_set
        end

        # @return [Array<PgEventstore::Subscription>]
        def subscriptions
          @subscriptions ||= subscription_queries.find_all(set: @current_set).map do |attrs|
            Subscription.new(**attrs)
          end
        end

        private

        # @return [PgEventstore::Connection]
        def connection
          PgEventstore.connection(@config)
        end

        # @return [PgEventstore::SubscriptionQueries]
        def subscription_queries
          SubscriptionQueries.new(connection)
        end
      end
    end
  end
end
