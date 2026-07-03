# frozen_string_literal: true

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.transaction do
    conn.exec(<<~SQL)
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
    SQL
    conn.exec(<<~SQL)
      CREATE INDEX idx_partitions_context_and_stream_name_search ON public.partitions
        USING GIN ((context || '#{PgEventstore::Event::SYSTEM_SYMBOL}' || stream_name) gin_trgm_ops)
        WHERE stream_name IS NOT NULL AND event_type IS NULL;
    SQL
    conn.exec(<<~SQL)
      CREATE INDEX idx_partitions_context_search ON public.partitions USING GIN (context gin_trgm_ops)
        WHERE stream_name IS NULL and event_type IS NULL;
      CREATE INDEX idx_partitions_event_type_search ON public.partitions USING GIN (event_type gin_trgm_ops)
        WHERE event_type IS NOT NULL;

      COMMENT ON INDEX idx_partitions_context_search IS 'Admin web UI search support.';
      COMMENT ON INDEX idx_partitions_context_and_stream_name_search IS 'Admin web UI search support.';
      COMMENT ON INDEX idx_partitions_event_type_search IS 'Admin web UI search support.';
    SQL
  end
end
