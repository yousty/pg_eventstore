CREATE UNIQUE INDEX idx_streams_context_and_stream_name_and_stream_id ON public.streams USING btree (context, stream_name, stream_id);
-- This index is used when searching by the specific stream and event's types
CREATE INDEX idx_events_stream_id_and_revision_and_type ON public.events USING btree (stream_id, stream_revision, type);

-- This index is used when searching by "all" stream using stream's attributes(context, stream_name, stream_id) and
-- event's types. PG's query planner picks this index when none of the given event's type exist
CREATE INDEX idx_events_type_and_stream_id_and_position ON public.events USING btree (type, stream_id, global_position);

-- This index is used when searching by "all" stream using stream's attributes(context, stream_name, stream_id) and
-- event's types. PG's query planner picks this index when some of the given event's types exist
CREATE INDEX idx_events_position_and_type ON public.events USING btree (global_position, type);

CREATE INDEX idx_events_link_id ON public.events USING btree (link_id);
