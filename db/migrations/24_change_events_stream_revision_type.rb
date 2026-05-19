# frozen_string_literal: true

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('ALTER TABLE public.events ALTER COLUMN stream_revision TYPE bigint')
  conn.exec('VACUUM (ANALYZE) public.events')
end
