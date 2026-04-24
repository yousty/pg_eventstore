# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventsGlobalIndexFiltering < BasicFiltering
      # @return [Integer]
      DEFAULT_LIMIT = 1_000
      # @return [String]
      PRIMARY_TABLE_NAME = 'events_global_index'

      class << self
        # @param options [Hash]
        # @return [PgEventstore::QueryBuilders::EventsGlobalIndexFiltering]
        def build_filter_from_query_options(options)
          index_filter = new
          index_filter.add_partition_filters(IndexPartitionsFilter.create(options, scope: :event_type))
          index_filter.from_position(options[:from_position], options[:direction])
          index_filter.to_position(options[:to_position], options[:direction])
          index_filter.add_direction(options[:direction])
          index_filter.add_limit(options[:max_count])
          index_filter
        end

        # @param options [Hash]
        # @return [PgEventstore::QueryBuilders::EventsGlobalIndexFiltering]
        def build_filter_from_subscription_options(options)
          index_filter = new
          index_filter.add_partition_filters(options[:index_partitions_filter])
          index_filter.from_position(options[:from_position], options[:direction])
          index_filter.to_position(options[:to_position], options[:direction])
          index_filter.add_direction(options[:direction])
          index_filter.add_limit(options[:max_count])
          index_filter
        end
      end

      # @return [String]
      def to_table_name
        PRIMARY_TABLE_NAME
      end

      # @param index_partitions_filter [PgEventstore::QueryBuilders::IndexPartitionsFilter]
      # @return [void]
      def add_partition_filters(index_partitions_filter)
        return if index_partitions_filter.empty?

        index_partitions_filter.with_stream_ids&.each do |builder|
          @sql_builder.where_or('(partition_id, stream_id) in ?', builder)
        end
        if index_partitions_filter.without_stream_id
          @sql_builder.where_or('partition_id in ?', index_partitions_filter.without_stream_id)
        end
      end

      # @param position [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def from_position(position, direction)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position #{direction_operator_from(direction)} ?", position)
      end

      # @param position [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def to_position(position, direction)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position #{direction_operator_to(direction)} ?", position)
      end

      # @param limit [Integer, nil]
      # @return [void]
      def add_limit(limit = DEFAULT_LIMIT)
        return unless limit

        @sql_builder.limit(limit)
      end

      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_direction(direction)
        @sql_builder.order("#{to_table_name}.global_position #{SQL_DIRECTIONS[direction]}")
      end

      # @param table_name [String] system stream view name
      # @return [void]
      # rubocop:disable Naming/AccessorMethodName
      def set_source(table_name)
        @sql_builder.from(%( "#{PG::Connection.escape(table_name)}" #{to_table_name} ))
      end
      # rubocop:enable Naming/AccessorMethodName

      private

      # @param direction [String, Symbol, nil]
      # @return [String]
      def direction_operator_from(direction)
        SQL_DIRECTIONS[direction] == 'ASC' ? '>=' : '<='
      end

      # @param direction [String, Symbol, nil]
      # @return [String]
      def direction_operator_to(direction)
        SQL_DIRECTIONS[direction] == 'ASC' ? '<=' : '>='
      end
    end
  end
end
