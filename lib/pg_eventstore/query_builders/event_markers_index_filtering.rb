# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventMarkersIndexFiltering
      include BasicFiltering

      # @return [String]
      PRIMARY_TABLE_NAME = 'event_markers_index'
      # @return [Integer]
      DEFAULT_LIMIT = 1_000

      class << self
        # @param marker_filter_row [PgEventstore::QueryBuilders::Filters::MarkerFilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @param seq_num [Integer]
        # @return [PgEventstore::SQLBuilder]
        def for_revision_validation_per_type(marker_filter_row, cursor, seq_num)
          builder = filtering_from_filter_row(marker_filter_row, cursor).to_sql_builder
          builder.unselect.select("stream_revision, #{seq_num} as sequence_number")
        end

        # @param marker_filter_row [PgEventstore::QueryBuilders::Filters::MarkerFilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def for_read_grouped(marker_filter_row, cursor)
          filtering_from_filter_row(marker_filter_row, cursor).to_sql_builder
        end

        # @param marker_filter_row [PgEventstore::QueryBuilders::Filters::MarkerFilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def for_read_common(marker_filter_row, cursor)
          filtering_from_filter_row(marker_filter_row, cursor).to_sql_builder
        end

        private

        # @param marker_filter_row [PgEventstore::QueryBuilders::Filters::MarkerFilterRow]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::QueryBuilders::EventMarkersIndexFiltering]
        def filtering_from_filter_row(marker_filter_row, cursor)
          index_filtering =
            # This is an optimization for the case when user reads from "all" stream and filters by the stream. We do
            # not have proper indexes to filter markers by stream and by global position. We calculate stream's revision
            # based on events_global_index data and filter by that revision instead. Yes, it results in one additional
            # subquery per marker filter, but it saves us from two additional indexes in event_markers_index table,
            # which is decent.
            if cursor.all_stream_cursor? && marker_filter_row.stream_filter&.stream?
              stream_revision_based_filtering(cursor, marker_filter_row)
            else
              default_filtering(cursor)
            end
          index_filtering.add_marker_filter_row(marker_filter_row)
          index_filtering
        end

        # @param index_filtering [PgEventstore::QueryBuilders::EventMarkersIndexFiltering]
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

        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::QueryBuilders::EventMarkersIndexFiltering]
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

        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @param marker_filter_row [PgEventstore::QueryBuilders::Filters::MarkerFilterRow]
        # @return [PgEventstore::QueryBuilders::EventMarkersIndexFiltering]
        def stream_revision_based_filtering(cursor, marker_filter_row)
          index_filtering = new
          # Translate from/to global position into from/to stream revision
          revision_from, revision_to = %i[from to].map do |notation|
            position = cursor.public_send(notation)
            next unless position

            events_idx_filtering = EventsGlobalIndexFiltering.new
            if notation == :from
              events_idx_filtering.add_global_position_direction(cursor.direction)
              events_idx_filtering.from_position(position, cursor.direction)
            else
              events_idx_filtering.add_global_position_direction(reverse_order(cursor.direction))
              events_idx_filtering.to_position(position, cursor.direction)
            end
            events_idx_filtering.add_filter_row(marker_filter_row.to_filter_row)
            events_idx_filtering.add_limit(1)


            events_idx_filtering.to_sql_builder.unselect.select('stream_revision')
          end

          index_filtering.add_stream_revision_direction(cursor.direction)
          index_filtering.from_revision(revision_from, cursor.direction) if revision_from
          index_filtering.to_revision(revision_to, cursor.direction) if revision_to
          index_filtering.add_limit(cursor.max_count)
          index_filtering
        end
      end

      def initialize
        @sql_builder = SQLBuilder.new
        @sql_builder.select("#{to_table_name}.global_position, #{to_table_name}.event_type_partition_id")
        @sql_builder.from(to_table_name)
      end

      def to_table_name
        PRIMARY_TABLE_NAME
      end

      def to_sql_builder
        @sql_builder
      end

      # @param marker_filter_row [PgEventstore::QueryBuilders::Filters::MarkerFilterRow]
      # @return [void]
      def add_marker_filter_row(marker_filter_row)
        stream_filter = marker_filter_row.stream_filter
        marker_filter = marker_filter_row.marker_filter

        query_parts = []
        if stream_filter&.stream?
          streams_filter = StreamsGlobalIndexFiltering.new
          filter_row = Filters::FilterRow.new(stream_filter:, event_type_filters: [])
          streams_filter.add_filter_row(filter_row)
          query_parts << [
            "#{to_table_name}.streams_global_index_id = ?", streams_filter.to_sql_builder.select_id_only
          ]
        end

        if marker_filter.event_type
          event_type_filter = Filters::EventTypeFilter.new(event_type: marker_filter.event_type, prefix: false)
          filter_row = Filters::FilterRow.new(stream_filter:, event_type_filters: [event_type_filter])
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row)
          query_parts <<
            if filter_row.ambiguous_event_type?
              [
                "#{to_table_name}.event_type_partition_id in ?",
                affected_partitions.select_id_only,
              ]
            else
              [
                "#{to_table_name}.event_type_partition_id = ?",
                affected_partitions.select_id_only,
              ]
            end
        elsif stream_filter && !stream_filter.stream?
          filter_row = Filters::FilterRow.new(stream_filter:, event_type_filters: [])
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row)
          query_parts << [
            "#{to_table_name}.event_type_partition_id = any(array(?)::bigint[])",
            affected_partitions.select_id_only,
          ]
        end

        markers_filtering = EventMarkersFiltering.new
        if marker_filter.markers.size == 1
          markers_filtering.add_name(marker_filter.markers.first)
          query_parts << ["#{to_table_name}.marker_id = ?", markers_filtering.to_sql_builder.select_id_only]
        else
          markers_filtering.add_names(marker_filter.markers)
          query_parts << [
            "#{to_table_name}.marker_id = any(array(?)::bigint[])",
            markers_filtering.to_sql_builder.select_id_only,
          ]
        end

        attributes_sql, values = query_parts.transpose
        @sql_builder.where_or(attributes_sql.join(' and '), *values)
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

      # @param position [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def from_position(position, direction)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position #{direction_operator_from(direction)} ?", position)
      end

      # @param revision [Integer, PgEventstore::SQLBuilder, nil]
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

      # @param revision [Integer, PgEventstore::SQLBuilder, nil]
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

      # @return [void]
      def for_subscription
        spos_table_name = EventSubscriptionPositionsFiltering::PRIMARY_TABLE_NAME
        @sql_builder.unselect.select(<<~SQL)
          distinct #{to_table_name}.global_position, #{to_table_name}.event_type_partition_id,
                   #{spos_table_name}.subscription_position
        SQL
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
    end
  end
end
