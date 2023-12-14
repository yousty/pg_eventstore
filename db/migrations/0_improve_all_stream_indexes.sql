CREATE INDEX idx_events_type_and_position ON public.events USING btree (type, global_position);
CREATE INDEX idx_events_global_position ON public.events USING btree (global_position);
DROP INDEX idx_events_position_and_type;
