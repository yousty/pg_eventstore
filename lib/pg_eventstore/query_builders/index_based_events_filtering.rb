# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    class IndexBasedEventsFiltering
      include BasicFiltering

      # @return [Integer]
      DEFAULT_LIMIT = 1_000
      # @return [String]
      ABSTRACT_TABLE_NAME = 'events_index'

      class << self
        # @param stream [PgEventstore::Stream]
        # @param expected_revision [PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevision]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_event_type_revision_validation(stream, expected_revision)
          cursor = QueryBuilders::ReadCursor::StreamCursor.from_stream_and_options(
            stream, { direction: :desc, max_count: 1 }
          )
          filters_collection = Filters::Collection.from_stream_and_options(
            stream, { filter: { event_types: [expected_revision.event_type] } }
          )
          rows = filters_collection.collection
          Utils.assert!(rows.size == 1, filters_collection.inspect)

          EventsGlobalIndexFiltering.for_revision_validation_per_type(
            rows.first, cursor, expected_revision.sequence_number
          )
        end

        # @param stream [PgEventstore::Stream]
        # @param expected_revision [PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevisionWithMarkers]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_event_type_with_markers_revision_validation(stream, expected_revision)
          cursor = QueryBuilders::ReadCursor::StreamCursor.from_stream_and_options(
            stream, { direction: :desc, max_count: 1 }
          )
          filters_collection = Filters::Collection.from_stream_and_options(
            stream,
            {
              filter: {
                event_types: [{ type: expected_revision.event_type, markers: expected_revision.markers }],
              },
            }
          )
          rows = filters_collection.collection
          Utils.assert!(rows.size == 1, filters_collection.inspect)

          builders = rows.first.flatten.map do |flattened|
            EventMarkersIndexFiltering.for_revision_validation_per_type(
              flattened, cursor, expected_revision.sequence_number
            )
          end
          final = SQLBuilder.new.select('*')
          final.from(SQLBuilder.union_builders(builders, mode: :union_distinct))
          final.order('stream_revision desc')
          final.limit(1)
        end

        # @param stream [PgEventstore::Stream]
        # @param expected_revision [PgEventstore::Commands::RevisionCheck::ExpectedRevision::MarkersRevision]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_markers_revision_validation(stream, expected_revision)
          cursor = QueryBuilders::ReadCursor::StreamCursor.from_stream_and_options(
            stream, { direction: :desc, max_count: 1 }
          )
          filters_collection = Filters::Collection.from_stream_and_options(
            stream, { filter: { event_types: [{ markers: expected_revision.markers }] } }
          )
          rows = filters_collection.collection
          Utils.assert!(rows.size == 1, filters_collection.inspect)

          builders = rows.first.flatten.map do |flattened|
            EventMarkersIndexFiltering.for_revision_validation_per_type(
              flattened, cursor, expected_revision.sequence_number
            )
          end
          final = SQLBuilder.new.select('*')
          final.from(SQLBuilder.union_builders(builders, mode: :union_distinct))
          final.order('stream_revision desc')
          final.limit(1)
        end

        # @param filter_rows [Array<PgEventstore::QueryBuilders::Filters::FilterRow,
        #   PgEventstore::QueryBuilders::Filters::MarkerFilterRow>]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_read_grouped(filter_rows, cursor)
          cursor = cursor.dup
          cursor.max_count = 1
          has_markers = false
          builders = filter_rows.flat_map do |filter_row|
            case filter_row
            when Filters::FilterRow
              filter_row.flatten.map do |flattened|
                EventsGlobalIndexFiltering.for_read_common(flattened, cursor)
              end
            when Filters::MarkerFilterRow
              has_markers ||= true
              filter_row.flatten.map do |flattened|
                EventMarkersIndexFiltering.for_read_common(flattened, cursor)
              end
            else
              Utils.missing_implementation!(filter_row)
            end
          end
          union_builders(builders, cursor, mode: has_markers ? :union_distinct : :union_all, requires_limit: false)
        end

        # @param filter_rows [Array<PgEventstore::QueryBuilders::Filters::FilterRow,
        #   PgEventstore::QueryBuilders::Filters::MarkerFilterRow>]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_read_common(filter_rows, cursor)
          return EventsGlobalIndexFiltering.default_filtering(cursor).to_sql_builder if filter_rows.empty?

          has_markers = false
          builders = filter_rows.flat_map do |filter_row|
            case filter_row
            when Filters::FilterRow
              filter_row.flatten.map do |flattened|
                EventsGlobalIndexFiltering.for_read_common(flattened, cursor)
              end
            when Filters::MarkerFilterRow
              has_markers ||= true
              filter_row.flatten.map do |flattened|
                EventMarkersIndexFiltering.for_read_common(flattened, cursor)
              end
            else
              Utils.missing_implementation!(filter_row)
            end
          end
          union_builders(builders, cursor, mode: has_markers ? :union_distinct : :union_all)
        end

        # @param filter_rows [Array<PgEventstore::QueryBuilders::Filters::FilterRow,
        #   PgEventstore::QueryBuilders::Filters::MarkerFilterRow>]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_estimate_count(filter_rows)
          cursor = ReadCursor::StreamCursor.from_options({})
          if filter_rows.empty?
            return EventsGlobalIndexFiltering.default_filtering(cursor).to_sql_builder.remove_limit.remove_order
          end

          has_markers = false
          builders = filter_rows.flat_map do |filter_row|
            case filter_row
            when Filters::FilterRow
              filter_row.flatten.map do |flattened|
                EventsGlobalIndexFiltering.for_read_common(flattened, cursor)
              end
            when Filters::MarkerFilterRow
              has_markers ||= true
              filter_row.flatten.map do |flattened|
                EventMarkersIndexFiltering.for_read_common(flattened, cursor)
              end
            else
              Utils.missing_implementation!(filter_row)
            end
          end
          builders.each { _1.remove_limit.remove_order }
          SQLBuilder.union_builders(builders, mode: has_markers ? :union_distinct : :union_all)
        end

        # @param filter_rows [Array<PgEventstore::QueryBuilders::Filters::FilterRow,
        #   PgEventstore::QueryBuilders::Filters::MarkerFilterRow>]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_for_subscriptions(filter_rows)
          if filter_rows.empty?
            sql_builder = EventsGlobalIndexFiltering.new.tap(&:for_subscription).to_sql_builder
            return finalize_subscription_builders([sql_builder])
          end

          builders = []
          grouped = filter_rows.group_by(&:class)
          grouped.each_value do |rows|
            case rows.first
            when Filters::FilterRow
              filtering = EventsGlobalIndexFiltering.new
              filtering.for_subscription
              rows.each(&filtering.method(:add_filter_row))
              builders.push(filtering.to_sql_builder)
            when Filters::MarkerFilterRow
              filtering = EventMarkersIndexFiltering.new
              filtering.for_subscription
              rows.each(&filtering.method(:add_marker_filter_row))
              builders.push(filtering.to_sql_builder)
            else
              Utils.missing_implementation!(rows.first)
            end
          end

          finalize_subscription_builders(builders)
        end

        private

        # @param builders [Array<PgEventstore::SQLBuilder>]
        # @return [PgEventstore::SQLBuilder]
        def finalize_subscription_builders(builders)
          return builders.first if builders.size == 1

          final = SQLBuilder.new.select(
            'events_idx.global_position, events_idx.event_type_partition_id, events_idx.subscription_position'
          )
          final.from(SQLBuilder.union_builders(builders, mode: :union_distinct), table_alias: 'events_idx')
          final.order('events_idx.subscription_position')
          final.limit('max_count')
        end

        # @param builders [Array<PgEventstore::SQLBuilder>]
        # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
        # @param mode [Symbol]
        # @param requires_limit [Boolean]
        # @return [PgEventstore::SQLBuilder]
        def union_builders(builders, cursor, mode:, requires_limit: true)
          return builders.first if builders.size == 1

          union_builder = SQLBuilder.union_builders(builders, mode:)
          top_filtering = new
          # Union builder always has fixed columns in SELECT (global_position and event_type_partition_id). Thus,
          # define SystemStreamOptions that is resolved to the sorting by global_position instead of possible
          # sorting by stream_revision which may not be present among the columns list
          cursor = ReadCursor::StreamCursor.from_options(direction: cursor.direction, max_count: cursor.max_count)
          top_filtering.add_global_position_direction(cursor.direction)
          top_filtering.add_limit(cursor.max_count) if requires_limit
          top_filtering.to_sql_builder.from(union_builder)
        end
      end

      def initialize
        @sql_builder = SQLBuilder.new
        @sql_builder.select('global_position, event_type_partition_id')
      end

      def to_table_name
        ''
      end

      def to_sql_builder
        @sql_builder
      end

      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_global_position_direction(direction)
        @sql_builder.order("global_position #{SQL_DIRECTIONS[direction]}")
      end

      # @param limit [Integer, nil]
      # @return [void]
      def add_limit(limit)
        @sql_builder.limit(limit || DEFAULT_LIMIT)
      end
    end
  end
end
