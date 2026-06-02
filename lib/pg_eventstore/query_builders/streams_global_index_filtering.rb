# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class StreamsGlobalIndexFiltering
      include BasicFiltering

      # @return [String]
      PRIMARY_TABLE_NAME = 'streams_global_index'
      # @return [Integer]
      DEFAULT_LIMIT = 1000

      class << self
        # @param options [Hash]
        # @option options [Integer, nil] :from_position
        # @option options [Integer, nil] :max_count
        # @option options [String, Symbol, nil] :direction
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_basic_pagination(options)
          streams_idx_filtering = QueryBuilders::StreamsGlobalIndexFiltering.new
          streams_idx_filtering.from_position(options[:from_position], options[:direction])
          streams_idx_filtering.limit(options[:max_count])
          streams_idx_filtering.add_starting_position_direction(options[:direction])
          streams_idx_filtering.to_sql_builder
        end
      end

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

      # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
      # @return [void]
      def add_filter_row(filter_row)
        affected_partitions = PartitionsFiltering.from_filter_row(filter_row, scope: :stream_name)
        builder = affected_partitions.unselect.select('id')
        @sql_builder.where_or('partition_id = ? and stream_id = ?', builder, filter_row.stream_filter.stream_id)
      end

      # @param position [Integer, nil]
      # @param direction [Symbol, String, nil]
      # @return [void]
      def from_position(position, direction)
        return if position.nil?

        @sql_builder.where("starting_position #{direction_operator_from(direction)} ?", position)
      end

      # @param limit [Integer, nil]
      # @return [void]
      def limit(limit)
        @sql_builder.limit(limit || DEFAULT_LIMIT)
      end

      # @param direction [Symbol, String, nil]
      # @return [void]
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
