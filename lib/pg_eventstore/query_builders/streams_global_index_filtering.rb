# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class StreamsGlobalIndexFiltering < BasicFiltering
      # @return [String]
      PRIMARY_TABLE_NAME = 'streams_global_index'

      class << self

      end

      # @return [String]
      def to_table_name
        PRIMARY_TABLE_NAME
      end

      # @param index_partitions_filter [PgEventstore::QueryBuilders::IndexPartitionsFilter]
      # @return [void]
      def add_partition_filters(index_partitions_filter)
        return if index_partitions_filter.empty?

        index_partitions_filter.for_streams_idx&.each do |builder|
          @sql_builder.where_or('(partition_id, stream_id) in ?', builder)
        end
      end
    end
  end
end
