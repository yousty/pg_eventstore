DROP INDEX idx_partitions_by_event_type;

CREATE INDEX idx_partitions_by_event_type_and_id ON public.partitions USING btree (event_type, id);
CREATE INDEX idx_partitions_by_context_and_stream_name_and_event_type_and_id ON public.partitions
    USING btree (context, stream_name, event_type, id);
