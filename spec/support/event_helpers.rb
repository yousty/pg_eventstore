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
  # @return [Array<PgEventstore::EventGlobalIndex>]
  def events_index(*events)
    builder = PgEventstore::QueryBuilders::EventsGlobalIndexFiltering.new.to_sql_builder
    builder.where('global_position = any(?)', events.map(&:global_position))
    result = PgEventstore.connection.with do |conn|
      conn.exec_params(*builder.to_exec_params)
    end
    result.map(&PgEventstore::EventGlobalIndex.method(:new))
  end
end
