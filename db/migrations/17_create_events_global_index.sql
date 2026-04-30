CREATE TABLE public.events_global_index
(
    global_position         bigint NOT NULL,
    partition_id            bigint NOT NULL,
    streams_global_index_id bigint NOT NULL
);

ALTER TABLE ONLY public.events_global_index
    ADD CONSTRAINT events_global_index_pkey PRIMARY KEY (global_position);

CREATE INDEX idx_events_global_index_on_partition_id_and_global_position ON public.events_global_index
    USING btree (partition_id, global_position);
CREATE INDEX idx_events_global_index_on_streams_idx_id_and_global_position ON public.events_global_index
    USING btree (streams_global_index_id, global_position);
CREATE INDEX idx_events_global_index_on_streams_idx_id_and_p_id_and_position ON public.events_global_index
    USING btree (streams_global_index_id, partition_id, global_position);
