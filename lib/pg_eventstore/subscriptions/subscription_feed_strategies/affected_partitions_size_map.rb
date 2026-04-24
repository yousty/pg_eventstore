# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategies
    class AffectedPartitionsSizeMap
      # A convention value to describe the number of partitions in "all" stream. We want it to be approximately big to
      # force index-based lookup for subscriptions without any filters
      # @return [Integer]
      ALL_PARTITIONS_NUMBER = 2**16

      attr_reader :last_partition_id

      def initialize(connection)
        @connection = connection
        @map = {}
        @last_partition_id = nil
      end

      # @param runners [Array<PgEventstore::SubscriptionRunner>]
      # @return [Boolean]
      def update_all(runners)
        max_partition_id = partition_queries.latest_partition_id
        return false if max_partition_id == @last_partition_id

        @last_partition_id = max_partition_id
        runners.each(&method(:update))
        true
      end

      # @param runner [PgEventstore::SubscriptionRunner]
      # @return [Integer] new affected partitions size
      def update(runner)
        if runner.index_partitions_filter.empty?
          @map[runner.id] = ALL_PARTITIONS_NUMBER
          return ALL_PARTITIONS_NUMBER
        end
        @map[runner.id] = partition_queries.count_from_index_partitions_filter(runner.index_partitions_filter)
      end

      # @param runner [PgEventstore::SubscriptionRunner]
      # @return [Integer] affected partitions size
      def affected_partitions_size(runner)
        @map[runner.id] || 0
      end

      private

      # @return [PgEventstore::PartitionQueries]
      def partition_queries
        PartitionQueries.new(@connection)
      end
    end
  end
end
