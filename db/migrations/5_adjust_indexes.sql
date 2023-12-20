CREATE INDEX idx_events_global_position ON public.events USING btree (global_position);

DROP INDEX idx_events_stream_id_and_type_and_revision;
DROP INDEX idx_events_type_and_stream_id_and_position;
DROP INDEX idx_events_global_position_including_type;
DROP INDEX idx_events_type_and_position;