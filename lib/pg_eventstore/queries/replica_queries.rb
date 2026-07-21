# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class ReplicaQueries
    MAX_PARTITIONS_TO_RESOLVE_PER_CALL = 100

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

    # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
    # @return [Array<Integer>]
    def load_subscription_positions(indexes)
      params = [indexes.first.subscription_position, indexes.last.subscription_position]
      exists = @query_strategy.exec_params(<<~SQL, params).first&.[]('one')
        select 1 as one from event_subscription_positions where subscription_position between $1 and $2 limit 1
      SQL
      return [] unless exists

      @query_strategy.exec_params(<<~SQL, [indexes.map(&:subscription_position)]).map { _1['subscription_position'] }
        select subscription_position from event_subscription_positions where subscription_position = any($1::bigint[])
      SQL
    end

    # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
    # @return [Array<PgEventstore::RawEvent>]
    def load_events(indexes)
      indexes = indexes.dup
      raw_events = []
      loop do
        range = Utils.range_to_slice(indexes.map(&:event_type_partition_id), MAX_PARTITIONS_TO_RESOLVE_PER_CALL)
        indexes_to_resolve = indexes.slice!(range)
        break if indexes_to_resolve.empty?

        raw_events.push(*events_global_index_queries.resolve_indexes(indexes_to_resolve, resolve_link_tos: false))
      end
      raw_events.map { RawEvent.new(**_1.transform_keys(&:to_sym)) }
    end

    # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
    # @return [Array<PgEventstore::EventGlobalIndex>]
    def load_events_global_index(indexes)
      result = @query_strategy.exec_params(<<~SQL, [indexes.map(&:global_position)])
        select * from events_global_index where global_position = any($1::bigint[])
      SQL
      result.map { EventGlobalIndex.new(**_1.transform_keys(&:to_sym)) }
    end

    # @param indexes [Array<PgEventstore::EventGlobalIndex>]
    # @return [Array<PgEventstore::StreamGlobalIndex>]
    def load_streams_global_index(indexes)
      result = @query_strategy.exec_params(<<~SQL, [indexes.map(&:streams_global_index_id)])
        select * from streams_global_index where id = any($1::bigint[])
      SQL
      stream_revisions_map = indexes.group_by(&:streams_global_index_id).to_h do |stream_id, events_idx|
        [stream_id, events_idx.max_by(&:stream_revision).stream_revision]
      end
      result.map do |attrs|
        attrs = attrs.transform_keys(&:to_sym)
        attrs[:stream_revision] = stream_revisions_map[attrs[:id]]
        StreamGlobalIndex.new(**attrs)
      end
    end

    # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
    # @return [Array<PgEventstore::EventMarkerIndex>]
    def load_event_markers_index(indexes)
      result = @query_strategy.exec_params(<<~SQL, [indexes.map(&:global_position)])
        select * from event_markers_index where global_position = any($1::bigint[])
      SQL
      result.map { EventMarkerIndex.new(**_1.transform_keys(&:to_sym)) }
    end

    # @param indexes [Array<PgEventstore::EventMarkerIndex>]
    # @return [Array<PgEventstore::EventMarker>]
    def load_markers(indexes)
      result = @query_strategy.exec_params(<<~SQL, [indexes.map(&:marker_id).uniq])
        select * from event_markers where id = any($1::bigint[])
      SQL
      result.map { EventMarker.new(**_1.transform_keys(&:to_sym)) }
    end

    # @param indexes [Array<PgEventstore::EventGlobalIndex>]
    # @return [Array<PgEventstore::Partition>]
    def load_partitions(indexes)
      ids = indexes.map(&:context_partition_id).uniq + indexes.map(&:stream_name_partition_id).uniq +
            indexes.map(&:event_type_partition_id).uniq
      result = @query_strategy.exec_params(<<~SQL, [ids])
        select * from partitions where id = any($1::bigint[]) order by id
      SQL
      result.map { Partition.new(**_1.transform_keys(&:to_sym)) }
    end

    private

    # @return [PgEventstore::EventsGlobalIndexQueries]
    def events_global_index_queries
      EventsGlobalIndexQueries.new(connection, @query_strategy)
    end
  end
end
