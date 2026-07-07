# frozen_string_literal: true

module EventHelpers
  UUID_REGEXP = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\z/i
  # @param stream [PgEventstore::Stream]
  # @return [Array<PgEventstore::Event>]
  def safe_read(stream)
    if stream.all_stream?
      PgEventstore.client.read(PgEventstore::Stream.all_stream)
    else
      PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { streams: [stream.to_hash] } })
    end
  end

  # @param events [PgEventstore::Event]
  # @return [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
  def read_api_indexes(*events)
    builder = PgEventstore::QueryBuilders::EventsGlobalIndexFiltering.new.to_sql_builder
    builder.where('global_position = any(?)', events.map(&:global_position))
    result = PgEventstore.connection.with do |conn|
      conn.exec_params(*builder.to_exec_params)
    end
    result = result.map do |attrs|
      attrs = PgEventstore::Utils.deep_transform_keys(attrs, &:to_sym)
      PgEventstore::EventGlobalIndex::ReadApiRepr.new(**attrs)
    end
    # Preserve the order at which we received events array
    result.sort_by do |read_api_idx|
      event = events.find { _1.global_position == read_api_idx.global_position }
      events.index(event)
    end
  end

  # @param value [Integer] position to reset to. The sequence starts with the given value
  def reset_events_subscription_position(value = 1)
    PgEventstore.connection.with do |conn|
      conn.exec("select setval('event_subscription_positions_subscription_position_seq'::regclass, #{value}, false)")
    end
  end

  # @param events [Array<PgEventstore::Event>]
  # @return [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
  def prepare_subscription_indexes(events)
    return [] if events.empty?

    PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection).assign_subscription_position
    index_filtering = PgEventstore::QueryBuilders::EventsGlobalIndexFiltering.new
    builder = index_filtering.to_sql_builder
    builder.join('join event_subscription_positions using(global_position)')
    builder.select('subscription_position')
    builder.where('events_global_index.global_position = any(?)', events.map(&:global_position))

    result = PgEventstore.connection.with do |conn|
      conn.exec_params(*builder.to_exec_params).map do |attrs|
        attrs = PgEventstore::Utils.deep_transform_keys(attrs, &:to_sym)
        PgEventstore::EventGlobalIndex::SubscriptionRepr.new(**attrs)
      end
    end
    # Preserve the order at which we received events array
    result.sort_by do |subscription_idx|
      event = events.find { _1.global_position == subscription_idx.global_position }
      events.index(event)
    end
  end

  # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
  # @return [PgEventstore::Chunks::SubscriptionEventsIndexChunk]
  def create_subscription_index_chunk(indexes, resolve_link_tos: false)
    query_strategy = PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection)
    PgEventstore::Chunks::SubscriptionEventsIndexChunk.new(
      indexes.dup, PgEventstore.connection, query_strategy, resolve_link_tos
    )
  end
end
