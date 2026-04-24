# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategies
    class Collection
      # This number is used to determine how many partitions we want to query within DirectRead strategy. Thus, we
      # produce one query containing up to this number of partitions to pull events. This allows to have more performant
      # queries for the cost of queries number.
      # The single runner that affects on more that this number of partitions will be processed by IndexRead strategy by
      # default.
      # @return [Integer]
      DEFAULT_PARTITIONS_PER_DIRECT_READ = 50

      class << self
        # @param runners [Array<PgEventstore::SubscriptionRunner>]
        # @param affected_partitions_size_map [PgEventstore::SubscriptionFeedStrategies::AffectedPartitionsSizeMap]
        # @param connection [PgEventstore::Connection]
        # @param query_strategy [PgEventstore::QueryStrategy]
        # @param partitions_per_direct_read [Integer]
        # @return [PgEventstore::SubscriptionFeedStrategies::Collection]
        def create(runners, affected_partitions_size_map, connection, query_strategy,
                   partitions_per_direct_read: DEFAULT_PARTITIONS_PER_DIRECT_READ)
          affected_partitions_size_map.update_all(runners)
          direct_read_group = []
          index_read = IndexRead.new(connection, query_strategy)
          direct_read = DirectRead.new(connection, query_strategy)
          current_direct_read_size = 0
          runners = runners.sort_by { affected_partitions_size_map.affected_partitions_size(_1) }
          runners.each do |runner|
            affected_partitions_size = affected_partitions_size_map.affected_partitions_size(runner)
            if affected_partitions_size <= partitions_per_direct_read
              if current_direct_read_size + affected_partitions_size > partitions_per_direct_read
                current_direct_read_size = 0
                direct_read_group.push(direct_read)
                direct_read = DirectRead.new(connection, query_strategy)
              else
                current_direct_read_size += affected_partitions_size
              end
              direct_read.add(runner)
            else
              index_read.add(runner)
            end
          end
          direct_read_group.push(direct_read) if direct_read.any?
          new.tap do |collection|
            collection.add(*direct_read_group)
            collection.add(index_read) if index_read.any?
          end
        end
      end

      def initialize
        @collection = []
      end

      def add(*groups)
        @collection.push(*groups)
      end

      def each(...)
        @collection.each(...)
      end
    end
  end
end
