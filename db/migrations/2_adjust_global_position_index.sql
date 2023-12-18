CREATE INDEX idx_events_global_position_including_type ON public.events USING btree (global_position) INCLUDE (type);
COMMENT ON INDEX idx_events_global_position_including_type IS 'Usually "type" column has low distinct values. Thus, composit index by "type" and "global_position" columns may not be picked by Query Planner properly. Improve an index by "global_position" by including "type" column which allows Query Planner to perform better by picking the correct index.';

DROP INDEX idx_events_global_position;
