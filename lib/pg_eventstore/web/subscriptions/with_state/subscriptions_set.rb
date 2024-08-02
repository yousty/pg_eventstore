# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      module WithState
        class SubscriptionsSet
          # @!attribute connection
          #   @return [PgEventstore::Connection]
          attr_reader :connection
          private :connection

          # @param connection [PgEventstore::Connection]
          # @param current_set [String, nil]
          # @param state [String]
          def initialize(connection, current_set, state:)
            @connection = connection
            @current_set = current_set
            @state = state
          end

          # @return [Array<PgEventstore::SubscriptionsSet>]
          def subscriptions_set
            @subscriptions_set ||=
              subscriptions_set_queries.find_all_by_subscription_state(name: @current_set, state: @state).map do |attrs|
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
end
