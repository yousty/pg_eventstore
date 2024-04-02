# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      class SubscriptionsSet
        # @param config [Symbol]
        # @param current_set [String, nil]
        def initialize(config, current_set)
          @config = config
          @current_set = current_set
        end

        # @return [Array<PgEventstore::SubscriptionsSet>]
        def subscriptions_set
          @subscriptions_set ||= subscriptions_set_queries.find_all(name: @current_set).map do |attrs|
            PgEventstore::SubscriptionsSet.new(**attrs)
          end
        end

        private

        # @return [PgEventstore::Connection]
        def connection
          PgEventstore.connection(@config)
        end

        # @return [PgEventstore::SubscriptionsSetQueries]
        def subscriptions_set_queries
          SubscriptionsSetQueries.new(connection)
        end
      end
    end
  end
end
