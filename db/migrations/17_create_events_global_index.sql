CREATE TABLE public.events_global_index
(
    global_position          bigint  NOT NULL,
    stream_revision          integer NOT NULL,
    context_partition_id     bigint  NOT NULL,
    stream_name_partition_id bigint  NOT NULL,
    event_type_partition_id  bigint  NOT NULL,
    streams_global_index_id  bigint  NOT NULL
);

CREATE INDEX idx_events_idx_on_global_position ON public.events_global_index USING btree (global_position);

-- (context, global_position)
CREATE INDEX idx_events_idx_on_ctx_part_id_N_position ON public.events_global_index
    USING btree (context_partition_id, global_position);

-- (context, stream_name, global_position)
CREATE INDEX idx_events_idx_on_stream_name_part_id_N_position ON public.events_global_index
    USING btree (stream_name_partition_id, global_position);

-- (context, stream_name, event_type, global_position)
CREATE INDEX idx_events_idx_on_e_type_part_id_N_position ON public.events_global_index
    USING btree (event_type_partition_id, global_position);

-- (context, stream_name, stream_id, global_position)
CREATE INDEX idx_events_idx_on_streams_idx_id_N_position ON public.events_global_index
    USING btree (streams_global_index_id, global_position);

-- (context, stream_name, stream_id, stream_revision)
CREATE INDEX idx_events_idx_on_streams_idx_id_N_revision ON public.events_global_index
    USING btree (streams_global_index_id, stream_revision);

-- (context, stream_name, event_type, stream_id, global_position)
CREATE INDEX idx_events_idx_on_streams_idx_id_N_e_type_part_id_n_position ON public.events_global_index
    USING btree (streams_global_index_id, event_type_partition_id, global_position);

-- (context, stream_name, event_type, stream_id, stream_revision)
CREATE INDEX idx_events_idx_on_streams_idx_id_N_e_type_part_id_n_revision ON public.events_global_index
    USING btree (streams_global_index_id, event_type_partition_id, stream_revision);
