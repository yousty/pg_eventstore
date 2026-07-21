DROP INDEX IF EXISTS idx_events_stream_id_and_stream_revision;
DROP INDEX IF EXISTS idx_events_stream_id_and_global_position;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_pkey;
