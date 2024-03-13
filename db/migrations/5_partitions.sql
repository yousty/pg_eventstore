CREATE TABLE public.partitions
(
    id          bigserial                         NOT NULL,
    context     character varying COLLATE "POSIX" NOT NULL,
    stream_name character varying COLLATE "POSIX",
    event_type  character varying COLLATE "POSIX",
    table_name  character varying COLLATE "POSIX" NOT NULL
);

ALTER TABLE ONLY public.partitions
    ADD CONSTRAINT partitions_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_partitions_by_context ON public.partitions USING btree (context) WHERE stream_name IS NULL AND event_type IS NULL;
CREATE UNIQUE INDEX idx_partitions_by_context_and_stream_name ON public.partitions USING btree (context, stream_name) WHERE event_type IS NULL;
CREATE UNIQUE INDEX idx_partitions_by_context_and_stream_name_and_event_type ON public.partitions USING btree (context, stream_name, event_type);
CREATE UNIQUE INDEX idx_partitions_by_partition_table_name ON public.partitions USING btree (table_name);
CREATE INDEX idx_partitions_by_event_type ON public.partitions USING btree (event_type);
