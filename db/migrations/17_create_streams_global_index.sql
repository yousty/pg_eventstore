CREATE TABLE public.streams_global_index
(
    id              bigserial                         NOT NULL,
    partition_id    bigint                            NOT NULL,
    stream_id       character varying COLLATE "POSIX" NOT NULL,
    stream_revision integer DEFAULT 0                 NOT NULL
);

COMMENT ON COLUMN public.streams_global_index.partition_id IS
    'Unlike partition_id of events_global_index - this one refers to (context, stream_name) partition where event_type is null';

ALTER TABLE ONLY public.streams_global_index
    ADD CONSTRAINT streams_global_index_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_streams_global_index_on_stream_id_and_partition_id ON public.streams_global_index
    USING btree (stream_id, partition_id);
