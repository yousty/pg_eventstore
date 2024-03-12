CREATE TABLE public.events
(
    id              uuid                        DEFAULT public.gen_random_uuid() NOT NULL,
    context         character varying COLLATE "POSIX"                            NOT NULL,
    stream_name     character varying COLLATE "POSIX"                            NOT NULL,
    stream_id       character varying COLLATE "POSIX"                            NOT NULL,
    global_position bigserial                                                    NOT NULL,
    stream_revision integer                                                      NOT NULL,
    data            jsonb                       DEFAULT '{}'::jsonb              NOT NULL,
    metadata        jsonb                       DEFAULT '{}'::jsonb              NOT NULL,
    link_id         uuid,
    created_at      timestamp without time zone DEFAULT now()                    NOT NULL,
    type            character varying COLLATE "POSIX"                            NOT NULL
) PARTITION BY LIST (context);

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (context, stream_name, type, global_position);

CREATE INDEX idx_events_stream_id_and_stream_revision ON public.events USING btree (stream_id, stream_revision);
CREATE INDEX idx_events_stream_id_and_global_position ON public.events USING btree (stream_id, global_position);

CREATE INDEX idx_events_id ON public.events USING btree (id);
CREATE INDEX idx_events_link_id ON public.events USING btree (link_id);
CREATE INDEX idx_events_global_position ON public.events USING btree (global_position);
