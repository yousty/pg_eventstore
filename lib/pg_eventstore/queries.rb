# frozen_string_literal: true

require_relative 'sql_builder'
require_relative 'query_builders/filters/collection'
require_relative 'query_builders/read_cursor/stream_cursor'
require_relative 'query_builders/basic_filtering'
require_relative 'query_builders/subscription_events_filtering'
require_relative 'query_builders/events_filtering'
require_relative 'query_builders/partitions_filtering'
require_relative 'query_builders/events_global_index_filtering'
require_relative 'query_builders/streams_global_index_filtering'
require_relative 'queries/transaction_queries'
require_relative 'queries/event_queries'
require_relative 'queries/partition_queries'
require_relative 'queries/links_resolver'
require_relative 'queries/maintenance_queries'
require_relative 'queries/events_global_index_queries'
require_relative 'queries/streams_global_index_queries'

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
    # @!attribute maintenance
    #   @return [PgEventstore::MaintenanceQueries, nil]
    attribute(:maintenance)
    # @!attribute maintenance
    #   @return [PgEventstore::EventsGlobalIndexQueries, nil]
    attribute(:events_global_index)
    # @!attribute maintenance
    #   @return [PgEventstore::StreamsGlobalIndexQueries, nil]
    attribute(:streams_global_index)
  end
end
