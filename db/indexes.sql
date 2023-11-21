CREATE INDEX idx_events_type ON public.events USING btree (type);
CREATE INDEX idx_events_ctx_and_stream_name_and_stream_id ON public.events USING btree (context, stream_name, stream_id);
CREATE INDEX idx_events_link_id ON public.events USING btree (link_id);
CREATE UNIQUE INDEX idx_events_id ON public.events USING btree (id);
