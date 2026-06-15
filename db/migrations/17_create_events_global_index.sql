CREATE TABLE public.events_global_index
(
    global_position          bigint NOT NULL,
    stream_revision          bigint NOT NULL,
    context_partition_id     bigint NOT NULL,
    stream_name_partition_id bigint NOT NULL,
    event_type_partition_id  bigint NOT NULL,
    streams_global_index_id  bigint NOT NULL
);

CREATE INDEX idx_events_idx_on_global_position ON public.events_global_index
    USING btree (global_position) INCLUDE (event_type_partition_id);

-- (context, global_position)
CREATE INDEX idx_events_idx_on_ctx_part_id_N_position ON public.events_global_index
    USING btree (context_partition_id, global_position) INCLUDE (event_type_partition_id);

-- (context, stream_name, global_position)
CREATE INDEX idx_events_idx_on_stream_name_part_id_N_position ON public.events_global_index
    USING btree (stream_name_partition_id, global_position) INCLUDE (event_type_partition_id);

-- (context, stream_name, event_type, global_position)
CREATE INDEX idx_events_idx_on_e_type_part_id_N_position ON public.events_global_index
    USING btree (event_type_partition_id, global_position);

-- (context, stream_name, stream_id, global_position)
CREATE INDEX idx_events_idx_on_streams_idx_id_N_position ON public.events_global_index
    USING btree (streams_global_index_id, global_position) INCLUDE (event_type_partition_id);

-- (context, stream_name, stream_id, stream_revision)
CREATE INDEX idx_events_idx_on_streams_idx_id_N_revision ON public.events_global_index
    USING btree (streams_global_index_id, stream_revision) INCLUDE (event_type_partition_id, global_position);

-- (context, stream_name, event_type, stream_id, global_position)
CREATE INDEX idx_events_idx_on_streams_idx_id_N_e_type_part_id_n_position ON public.events_global_index
    USING btree (streams_global_index_id, event_type_partition_id, global_position);

-- (context, stream_name, event_type, stream_id, stream_revision)
CREATE INDEX idx_events_idx_on_streams_idx_id_N_e_type_part_id_n_revision ON public.events_global_index
    USING btree (streams_global_index_id, event_type_partition_id, stream_revision) INCLUDE (global_position);

CREATE TABLE public.event_subscription_positions
(
    global_position       bigint    NOT NULL,
    subscription_position bigserial NOT NULL
);

CREATE TABLE public.event_subscription_positions_unprocessed
(
    global_position bigint NOT NULL
);

CREATE INDEX idx_event_subscription_positions_sposition_N_gposition ON public.event_subscription_positions
    USING btree (subscription_position, global_position);

CREATE INDEX idx_event_subscription_positions_gposition_N_sposition ON public.event_subscription_positions
    USING btree (global_position, subscription_position);

CREATE INDEX idx_event_subscription_positions_unprocessed_gposition ON public.event_subscription_positions_unprocessed
    USING btree (global_position);
