# frozen_string_literal: true

require_relative 'queries/transaction_queries'
require_relative 'queries/event_queries'
require_relative 'queries/stream_queries'
require_relative 'queries/event_type_queries'
require_relative 'queries/subscription_queries'
require_relative 'queries/subscriptions_set_queries'

module PgEventstore
  # @!visibility private
  class Queries
    include Extensions::OptionsExtension

    # @!attribute events
    #   @return [PgEventstore::EventQueries, nil]
    attribute(:events)
    # @!attribute streams
    #   @return [PgEventstore::StreamQueries, nil]
    attribute(:streams)
    # @!attribute transactions
    #   @return [PgEventstore::TransactionQueries, nil]
    attribute(:transactions)
  end
end
