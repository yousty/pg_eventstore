# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class StreamsGlobalIndexFiltering
      include BasicFiltering

      # @return [String]
      PRIMARY_TABLE_NAME = 'streams_global_index'

      def initialize
        @sql_builder = SQLBuilder.new.select("#{to_table_name}.*").from(to_table_name)
      end

      def to_sql_builder
        @sql_builder
      end

      # @return [String]
      def to_table_name
        PRIMARY_TABLE_NAME
      end

      def add_filter_row(filter_row)
        affected_partitions = PartitionsFiltering.from_filter_row(filter_row, scope: :stream_name)
        builder = affected_partitions.unselect.select('id')
        @sql_builder.where_or('partition_id = ? and stream_id = ?', builder, filter_row.stream_filter.stream_id)
      end
    end
  end
end
