# frozen_string_literal: true

module PgEventstore
  class IndexFilteringQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    # @param query_strategy [PgEventstore::QueryStrategy]
    def initialize(connection, query_strategy)
      @connection = connection
      @query_strategy = query_strategy
    end

    # @param stream [PgEventstore::Stream]
    # @param expected_revisions [Array<PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevision,
    #   PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevisionWithMarkers,
    #   PgEventstore::Commands::RevisionCheck::ExpectedRevision::MarkersRevision>]
    # @return [Array<PgEventstore::EventGlobalIndex::RevisionCheckRepr>]
    def fetch_indexes_for_revision_validation(stream, expected_revisions)
      builders = expected_revisions.map do |expected_revision|
        case expected_revision
        when Commands::RevisionCheck::ExpectedRevision::EventTypeRevision
          QueryBuilders::IndexBasedEventsFiltering.sql_builder_for_event_type_revision_validation(
            stream, expected_revision
          )
        when Commands::RevisionCheck::ExpectedRevision::EventTypeRevisionWithMarkers
          QueryBuilders::IndexBasedEventsFiltering.sql_builder_for_event_type_with_markers_revision_validation(
            stream, expected_revision
          )
        when Commands::RevisionCheck::ExpectedRevision::MarkersRevision
          QueryBuilders::IndexBasedEventsFiltering.sql_builder_for_markers_revision_validation(
            stream, expected_revision
          )
        else
          Utils.missing_implementation!(expected_revision)
        end
      end
      final = SQLBuilder.union_builders(builders)
      deserialize(@query_strategy.exec_params(*final.to_exec_params), repr: EventGlobalIndex::ReprType::REVISION_CHECK)
    end

    # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
    # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
    # @return [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
    def fetch_indexes_for_read_api(filters_collection, cursor)
      filter_rows =
        if filters_collection.collection.any?(&:ambiguous_event_type?)
          expand_event_types(filters_collection)
        else
          filters_collection.collection
        end

      sql_builder = QueryBuilders::IndexBasedEventsFiltering.sql_builder_for_read_common(filter_rows, cursor)
      deserialize(@query_strategy.exec_params(*sql_builder.to_exec_params), repr: EventGlobalIndex::ReprType::READ_API)
    end

    # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
    # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
    # @return [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
    def fetch_grouped_indexes_for_read_api(filters_collection, cursor)
      filter_rows =
        if filters_collection.collection.any?(&:ambiguous_event_type?)
          expand_event_types(filters_collection)
        else
          filters_collection.collection
        end

      sql_builder = QueryBuilders::IndexBasedEventsFiltering.sql_builder_for_read_grouped(filter_rows, cursor)
      deserialize(@query_strategy.exec_params(*sql_builder.to_exec_params), repr: EventGlobalIndex::ReprType::READ_API)
    end

    # @param indexes [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
    # @param resolve_link_tos [Boolean]
    # @return [PgEventstore::Chunks::Repository]
    def compute_read_api_chunks_repo(indexes, resolve_link_tos)
      repo = Chunks::Repository.new
      repo.add_chunk(Chunks::ReadApiEventsIndexChunk.new(indexes, connection, @query_strategy, resolve_link_tos))
      repo
    end

    private

    # @return [PgEventstore::PartitionQueries]
    def partition_queries
      PartitionQueries.new(connection)
    end

    # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
    # @return [Array<PgEventstore::QueryBuilders::Filters::FilterRow>]
    def expand_event_types(filters_collection)
      filter_rows = filters_collection.collection
      to_expand = filter_rows.select(&:ambiguous_event_type?)
      rest_filter_rows = filter_rows - to_expand
      partition_builders = to_expand.map do |filter_row|
        partitions_filtering = QueryBuilders::PartitionsFiltering.new
        partitions_filtering.with_event_types
        filter_row = filter_row.to_filter_row if filter_row.is_a?(QueryBuilders::Filters::MarkerFilterRow)
        partitions_filtering.add_filter_row(filter_row)
        partitions_filtering.to_sql_builder.unselect.select('context, stream_name, event_type')
      end
      final_partition_builder = SQLBuilder.union_builders(partition_builders)
      expanded_partitions_list = @query_strategy.exec_params(*final_partition_builder.to_exec_params)
      expanded_partitions_list = expanded_partitions_list.group_by { _1['event_type'] }
      expanded_filter_rows =
        to_expand.flat_map do |filter_row|
          case filter_row
          when QueryBuilders::Filters::FilterRow
            filter_row.event_type_filters.flat_map do |event_type_filter|
              related_partitions =
                if event_type_filter.prefix?
                  expanded_partitions_list.select do |event_type, _|
                    event_type.start_with?(event_type_filter.event_type)
                  end.values.flatten
                else
                  expanded_partitions_list[event_type_filter.event_type]
                end
              next [] unless related_partitions

              if filter_row.stream_filter
                related_partitions = related_partitions.select do |attrs|
                  if filter_row.stream_filter.context?
                    attrs['context'] == filter_row.stream_filter.context
                  else
                    attrs['context'] == filter_row.stream_filter.context &&
                      attrs['stream_name'] == filter_row.stream_filter.stream_name
                  end
                end
              end
              related_partitions.map do |partition_attrs|
                stream_filter = QueryBuilders::Filters::StreamFilter.new(
                  context: partition_attrs['context'],
                  stream_name: partition_attrs['stream_name']
                )
                event_type_filter = QueryBuilders::Filters::EventTypeFilter.new(
                  event_type: partition_attrs['event_type'], prefix: false
                )
                QueryBuilders::Filters::FilterRow.new(stream_filter:, event_type_filters: [event_type_filter])
              end
            end
          when QueryBuilders::Filters::MarkerFilterRow
            related_partitions = expanded_partitions_list[filter_row.marker_filter.event_type]
            next [] unless related_partitions

            if filter_row.stream_filter
              related_partitions = related_partitions.select do |attrs|
                attrs['context'] == filter_row.stream_filter.context
              end
            end
            related_partitions.map do |partition_attrs|
              stream_filter = QueryBuilders::Filters::StreamFilter.new(
                context: partition_attrs['context'],
                stream_name: partition_attrs['stream_name']
              )
              QueryBuilders::Filters::MarkerFilterRow.new(stream_filter:, marker_filter: filter_row.marker_filter.dup)
            end
          else
            Utils.missing_implementation!(filter_row)
          end
        end
      adjusted_rows = expanded_filter_rows + rest_filter_rows
      return [QueryBuilders::Filters::FilterRow.null_filter_row] if adjusted_rows.empty?

      adjusted_rows
    end

    # @param repr [Symbol, nil]
    # @return [Array<PgEventstore::EventGlobalIndex>, Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>,
    #   Array<PgEventstore::EventGlobalIndex::ReadApiRepr>, Array<PgEventstore::EventGlobalIndex::WriteApiRepr>,
    #   Array<PgEventstore::EventGlobalIndex::RevisionCheckRepr>]
    def deserialize(pg_result, repr: nil)
      pg_result.map do |attrs|
        EventGlobalIndex.create_representation(attrs.transform_keys(&:to_sym), repr:)
      end
    end
  end
end
