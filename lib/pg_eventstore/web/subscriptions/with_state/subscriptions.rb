# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      module WithState
        class Subscriptions
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

          # @return [Array<PgEventstore::Subscription>]
          def subscriptions
            @subscriptions ||= subscription_queries.find_all(set: @current_set, state: @state).map do |attrs|
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
end
