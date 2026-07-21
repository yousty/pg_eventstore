# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventMarkerQueries
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

    # @param names [Array<String>]
    # @return [Array<PgEventstore::EventMarker>]
    def find_or_create_by(names)
      builder = QueryBuilders::EventMarkersFiltering.sql_builder_by_names(names)
      existing = @query_strategy.exec_params(*builder.to_exec_params)
      existing = deserialize(existing)
      rest = names - existing.map(&:name)
      return existing if rest.empty?

      values = rest.map do |name|
        "('#{PG::Connection.escape(name)}')"
      end.join(',')
      table_name = QueryBuilders::EventMarkersFiltering::PRIMARY_TABLE_NAME
      rest = @query_strategy.exec(<<~SQL)
        insert into #{table_name} ("name") values #{values} returning *
      SQL
      existing + deserialize(rest)
    end

    # @param stream_idx_id [Integer]
    # @param write_api_events_index [Array<PgEventstore::EventGlobalIndex::WriteApiRepr>]
    # @param revision_to_marker_ids_map [Hash<Integer, Set<Integer>>]
    # @return [void]
    def create_indexes(stream_idx_id, write_api_events_index, revision_to_marker_ids_map)
      offset = write_api_events_index.first.stream_revision
      values = revision_to_marker_ids_map.flat_map do |stream_revision, marker_ids|
        event_index = write_api_events_index[stream_revision - offset]
        marker_ids.map do |marker_id|
          values = [
            marker_id,
            stream_idx_id,
            event_index.global_position,
            event_index.stream_revision,
            event_index.event_type_partition_id,
          ]
          "(#{values.join(',')})"
        end
      end
      values = values.join(', ')
      table_name = QueryBuilders::EventMarkersIndexFiltering::PRIMARY_TABLE_NAME
      @query_strategy.exec(<<~SQL)
        insert into #{table_name}
        ("marker_id", "streams_global_index_id", "global_position", "stream_revision", "event_type_partition_id")
        values
        #{values}
      SQL
    end

    private

    # @param pg_result [PG::Result]
    # @return [Array<PgEventstore::EventMarker>]
    def deserialize(pg_result)
      pg_result.map { EventMarker.new(**_1.transform_keys(&:to_sym)) }
    end
  end
end
