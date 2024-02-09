CREATE TABLE public.streams
(
    id              bigserial                     NOT NULL,
    context         character varying             NOT NULL,
    stream_name     character varying             NOT NULL,
    stream_id       character varying             NOT NULL,
    stream_revision integer DEFAULT '-1'::integer NOT NULL
);

ALTER TABLE ONLY public.streams
    ADD CONSTRAINT streams_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_streams_context_and_stream_name_and_stream_id ON public.streams USING btree (context, stream_name, stream_id);
