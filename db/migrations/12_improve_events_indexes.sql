CREATE INDEX idx_events_event_type_id_and_global_position ON public.events USING btree (event_type_id, global_position);
