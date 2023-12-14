CREATE INDEX idx_events_stream_id_and_type_and_revision ON public.events USING btree (stream_id, type, stream_revision);
CREATE INDEX idx_events_stream_id_and_revision ON public.events USING btree (stream_id, stream_revision);
DROP INDEX idx_events_stream_id_and_revision_and_type;
