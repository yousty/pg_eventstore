# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class StreamsGlobalIndexFiltering
      include BasicFiltering

      # @return [String]
      PRIMARY_TABLE_NAME = 'streams_global_index'
      DEFAULT_LIMIT = 1000

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

      def from_position(position, direction)
        return if position.nil?

        @sql_builder.where("starting_position #{direction_operator_from(direction)} ?", position)
      end

      def limit(limit)
        limit ||= DEFAULT_LIMIT
        @sql_builder.limit(limit)
      end

      def add_starting_position_direction(direction)
        @sql_builder.order("#{to_table_name}.starting_position #{SQL_DIRECTIONS[direction]}")
      end

      private

      # @param direction [String, Symbol, nil]
      # @return [String]
      def direction_operator_from(direction)
        SQL_DIRECTIONS[direction] == 'ASC' ? '>=' : '<='
      end
    end
  end
end
