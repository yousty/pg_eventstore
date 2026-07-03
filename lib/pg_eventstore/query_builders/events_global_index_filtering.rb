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
        # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @param seq_num [Integer]
        # @return [PgEventstore::SQLBuilder]
        def for_revision_validation_per_type(filter_row, cursor, seq_num)
          builder = filtering_from_filter_row(filter_row, cursor).to_sql_builder
          builder.unselect.select("stream_revision, #{seq_num} as sequence_number")
        end

        # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def for_read_grouped(filter_row, cursor)
          filtering_from_filter_row(filter_row, cursor).to_sql_builder
        end

        # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def for_read_common(filter_row, cursor)
          filtering_from_filter_row(filter_row, cursor).to_sql_builder
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

        private

        # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::QueryBuilders::EventsGlobalIndexFiltering]
        def filtering_from_filter_row(filter_row, cursor)
          index_filtering = default_filtering(cursor)
          index_filtering.add_filter_row(filter_row)
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
        operator, rhs = event_type_comparison(filter_row)
        # Collapse context/stream name & event type filters into event type filters
        if filter_row.collapsable_into_event_types_only?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row)
          partitions_builder = affected_partitions.select_id_only
          return @sql_builder.where_or(
            "#{to_table_name}.event_type_partition_id #{operator} #{rhs}",
            partitions_builder
          )
        end

        query_parts = []
        if stream_filter&.stream?
          streams_filter = StreamsGlobalIndexFiltering.new
          streams_filter.add_filter_row(filter_row)
          query_parts << [
            "#{to_table_name}.streams_global_index_id = ?", streams_filter.to_sql_builder.select_id_only
          ]
        elsif stream_filter&.context?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row, scope: :context)
          query_parts << ["#{to_table_name}.context_partition_id = ?", affected_partitions.select_id_only]
        elsif stream_filter&.stream_name?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row, scope: :stream_name)
          query_parts << ["#{to_table_name}.stream_name_partition_id = ?", affected_partitions.select_id_only]
        end

        if event_type_filters.any?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row)
          query_parts << [
            "#{to_table_name}.event_type_partition_id #{operator} #{rhs}",
            affected_partitions.select_id_only,
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

      # @return [void]
      def for_subscription
        spos_table_name = EventSubscriptionPositionsFiltering::PRIMARY_TABLE_NAME
        @sql_builder.select("#{spos_table_name}.subscription_position")
        @sql_builder.join("join #{spos_table_name} using(global_position)")
        @sql_builder.where("#{spos_table_name}.subscription_position >= from_position")
        @sql_builder.where("#{spos_table_name}.subscription_position <= to_position")
        @sql_builder.where("#{to_table_name}.global_position >= from_gpos")
        @sql_builder.where("#{to_table_name}.global_position <= to_gpos")
        @sql_builder.order("#{spos_table_name}.subscription_position asc")
        @sql_builder.limit('max_count')
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
      # @return [Array<String>]
      def event_type_comparison(filter_row)
        if filter_row.event_type_filters.size > 1 || filter_row.ambiguous_event_type?
          ['=', 'any(array(?)::bigint[])']
        else
          ['=', '?']
        end
      end
    end
  end
end
