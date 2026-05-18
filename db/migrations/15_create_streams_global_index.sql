CREATE TABLE public.streams_global_index
(
    id                bigserial                         NOT NULL,
    partition_id      bigint                            NOT NULL,
    stream_id         character varying COLLATE "POSIX" NOT NULL,
    stream_revision   bigint                            NOT NULL,
    starting_position bigint                            NOT NULL
);

ALTER TABLE ONLY public.streams_global_index
    ADD CONSTRAINT streams_global_index_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_streams_global_index_on_stream_id_and_partition_id ON public.streams_global_index
    USING btree (stream_id, partition_id);

CREATE INDEX idx_streams_global_index_on_starting_position ON public.streams_global_index
    USING btree (starting_position);
