# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventsGlobalIndexFiltering
      include BasicFiltering

      # @return [Integer]
      DEFAULT_LIMIT = 1_000
      # @return [String]
      PRIMARY_TABLE_NAME = 'events_global_index'

      class << self
        # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_revision_validation_per_type(filters_collection, cursor)
          raise ArgumentError, 'Can not build this query using "all" stream cursor.' if cursor.all_stream_cursor?

          cursor = cursor.dup
          cursor.max_count = 1
          builders = filters_collection.collection.flat_map do |filter_row|
            filter_row.flatten.map do |flattened_row|
              builder = filtering_from_filter_row(flattened_row, cursor).to_sql_builder
              builder.select('stream_revision')
            end
          end
          SQLBuilder.union_builders(builders, mode: :all)
        end

        # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_read_grouped(filters_collection, cursor)
          cursor = cursor.dup
          cursor.max_count = 1
          builders = filters_collection.collection.flat_map do |filter_row|
            filter_row.flatten.map { filtering_from_filter_row(_1, cursor).to_sql_builder }
          end
          # Do not limit final result
          cursor.max_count = nil
          union_builders(builders, cursor, mode: :all)
        end

        # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_read_common(filters_collection, cursor)
          builders = filters_collection.collection.flat_map do |filter_row|
            filter_row.flatten.map { filtering_from_filter_row(_1, cursor).to_sql_builder }
          end
          return default_filtering(cursor).to_sql_builder if builders.empty?

          union_builders(builders, cursor, mode: :all)
        end

        private

        # @param builders [Array<PgEventstore::SQLBuilder>]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @param mode [Symbol]
        # @return [PgEventstore::SQLBuilder]
        def union_builders(builders, cursor, mode:)
          return builders.first if builders.size == 1

          union_builder = SQLBuilder.union_builders(builders, mode:)
          top_filtering = new
          # Union builder always has fixed columns in SELECT (global_position and event_type_partition_id). Thus,
          # define SystemStreamOptions that is resolved to the sorting by global_position instead of possible
          # sorting by stream_revision which may not be present among the columns list
          cursor = ReadCursor::StreamCursor.from_options(direction: cursor.direction, max_count: cursor.max_count)
          add_direction_and_limit(top_filtering, cursor)
          top_filtering.to_sql_builder.from(union_builder)
        end

        # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::QueryBuilders::EventsGlobalIndexFiltering]
        def filtering_from_filter_row(filter_row, cursor)
          index_filtering = default_filtering(cursor)
          index_filtering.add_filter_row(filter_row)
          index_filtering
        end

        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::QueryBuilders::EventsGlobalIndexFiltering]
        def default_filtering(cursor)
          index_filtering = new
          add_direction_and_limit(index_filtering, cursor)
          if cursor.all_stream_cursor?
            index_filtering.from_position(cursor.from, cursor.direction)
            index_filtering.to_position(cursor.to, cursor.direction)
          else
            index_filtering.from_revision(cursor.from, cursor.direction)
            index_filtering.to_revision(cursor.to, cursor.direction)
          end
          index_filtering
        end

        # @param index_filtering [PgEventstore::QueryBuilders::EventsGlobalIndexFiltering]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [void]
        def add_direction_and_limit(index_filtering, cursor)
          if cursor.all_stream_cursor?
            index_filtering.add_global_position_direction(cursor.direction)
          else
            index_filtering.add_stream_revision_direction(cursor.direction)
          end
          index_filtering.add_limit(cursor.max_count)
        end
      end

      def initialize
        @sql_builder = SQLBuilder.new
        @sql_builder.select("#{to_table_name}.global_position, #{to_table_name}.event_type_partition_id")
        @sql_builder.from(to_table_name)
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
        stream_filter = filter_row.stream_filter
        event_type_filters = filter_row.event_type_filters
        event_type_comparison_operator = event_type_comparison_operator(filter_row)
        # Collapse context/stream name & event type filters into event type filters
        if filter_row.collapsable_into_event_types_only?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row)
          partitions_builder = affected_partitions.unselect.select('id')
          return @sql_builder.where_or(
            "event_type_partition_id #{event_type_comparison_operator} ?",
            partitions_builder
          )
        end

        query_parts = []
        if stream_filter&.stream?
          streams_filter = StreamsGlobalIndexFiltering.new
          streams_filter.add_filter_row(filter_row)
          query_parts << ['streams_global_index_id = ?', streams_filter.to_sql_builder.unselect.select('id')]
        elsif stream_filter&.context?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row, scope: :context)
          query_parts << ['context_partition_id = ?', affected_partitions.unselect.select('id')]
        elsif stream_filter&.stream_name?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row, scope: :stream_name)
          query_parts << ['stream_name_partition_id = ?', affected_partitions.unselect.select('id')]
        end

        if event_type_filters.any?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row)
          query_parts << [
            "event_type_partition_id #{event_type_comparison_operator} ?",
            affected_partitions.unselect.select('id'),
          ]
        end

        attributes_sql, values = query_parts.transpose
        @sql_builder.where_or(attributes_sql.join(' and '), *values)
      end

      # @param position [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def from_position(position, direction)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position #{direction_operator_from(direction)} ?", position)
      end

      # @param revision [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def from_revision(revision, direction)
        return unless revision

        @sql_builder.where("#{to_table_name}.stream_revision #{direction_operator_from(direction)} ?", revision)
      end

      # @param position [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def to_position(position, direction)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position #{direction_operator_to(direction)} ?", position)
      end

      # @param revision [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def to_revision(revision, direction)
        return unless revision

        @sql_builder.where("#{to_table_name}.stream_revision #{direction_operator_to(direction)} ?", revision)
      end

      # @param limit [Integer, nil]
      # @return [void]
      def add_limit(limit)
        @sql_builder.limit(limit || DEFAULT_LIMIT)
      end

      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_global_position_direction(direction)
        @sql_builder.order("#{to_table_name}.global_position #{SQL_DIRECTIONS[direction]}")
      end

      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_stream_revision_direction(direction)
        @sql_builder.order("#{to_table_name}.stream_revision #{SQL_DIRECTIONS[direction]}")
      end

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

      # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
      # @return [String]
      def event_type_comparison_operator(filter_row)
        if filter_row.event_type_filters.size > 1 || filter_row.ambiguous_event_type? ||
           filter_row.event_type_filters.any?(&:prefix?)
          return 'in'
        end

        '='
      end
    end
  end
end
