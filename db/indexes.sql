CREATE UNIQUE INDEX idx_streams_context_and_stream_name_and_stream_id ON public.streams USING btree (context, stream_name, stream_id);
CREATE INDEX idx_events_stream_id_and_revision_and_type ON public.events USING btree (stream_id, stream_revision, type);
CREATE INDEX idx_events_stream_id_and_position_and_type ON public.events USING btree (stream_id, global_position, type);
CREATE INDEX idx_events_link_id ON public.events USING btree (link_id);
CREATE UNIQUE INDEX idx_events_global_position ON public.events USING btree (global_position);
