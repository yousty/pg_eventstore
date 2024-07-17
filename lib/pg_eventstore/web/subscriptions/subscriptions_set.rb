# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      class SubscriptionsSet
        # @!attribute connection
        #   @return [PgEventstore::Connection]
        attr_reader :connection
        private :connection

        # @param connection [PgEventstore::Connection]
        # @param current_set [String, nil]
        def initialize(connection, current_set)
          @connection = connection
          @current_set = current_set
        end

        # @return [Array<PgEventstore::SubscriptionsSet>]
        def subscriptions_set
          @subscriptions_set ||= subscriptions_set_queries.find_all(name: @current_set).map do |attrs|
            PgEventstore::SubscriptionsSet.new(**attrs)
          end
        end

        private

        # @return [PgEventstore::SubscriptionsSetQueries]
        def subscriptions_set_queries
          SubscriptionsSetQueries.new(connection)
        end
      end
    end
  end
end
