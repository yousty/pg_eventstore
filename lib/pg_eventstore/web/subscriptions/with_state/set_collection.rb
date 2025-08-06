# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      module WithState
        class SetCollection
          # @!attribute connection
          #   @return [PgEventstore::Connection]
          attr_reader :connection
          private :connection

          # @param connection [PgEventstore::Connection]
          # @param state [String]
          def initialize(connection, state:)
            @connection = connection
            @state = state
          end

          # @return [Array<String>]
          def names
            @names ||= subscription_queries.set_collection(@state)
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
