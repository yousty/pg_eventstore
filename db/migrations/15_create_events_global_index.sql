CREATE TABLE public.events_global_index
(
    global_position bigint                            NOT NULL,
    partition_id    bigint                            NOT NULL,
    stream_id       character varying COLLATE "POSIX" NOT NULL
);

ALTER TABLE ONLY public.events_global_index
    ADD CONSTRAINT events_global_index_pkey PRIMARY KEY (global_position, partition_id, stream_id);
