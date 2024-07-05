# frozen_string_literal: true

require_relative 'sql_builder'
require_relative 'query_builders/events_filtering_query'
require_relative 'queries/transaction_queries'
require_relative 'queries/event_queries'
require_relative 'queries/partition_queries'
require_relative 'queries/links_resolver'

module PgEventstore
  # @!visibility private
  class Queries
    include Extensions::OptionsExtension

    # @!attribute events
    #   @return [PgEventstore::EventQueries, nil]
    attribute(:events)
    # @!attribute partitions
    #   @return [PgEventstore::PartitionQueries, nil]
    attribute(:partitions)
    # @!attribute transactions
    #   @return [PgEventstore::TransactionQueries, nil]
    attribute(:transactions)
  end
end
