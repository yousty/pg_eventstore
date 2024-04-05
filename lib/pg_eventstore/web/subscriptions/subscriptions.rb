# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      class Subscriptions
        attr_reader :connection
        private :connection

        # @param connection [PgEventstore::Connection]
        # @param current_set [String]
        def initialize(connection, current_set)
          @connection = connection
          @current_set = current_set
        end

        # @return [Array<PgEventstore::Subscription>]
        def subscriptions
          @subscriptions ||= subscription_queries.find_all(set: @current_set).map do |attrs|
            Subscription.new(**attrs)
          end
        end

        private

        # @return [PgEventstore::SubscriptionQueries]
        def subscription_queries
          SubscriptionQueries.new(connection)
        end
      end
    end
  end
end
