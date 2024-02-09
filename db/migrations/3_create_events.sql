CREATE TABLE public.events
(
    id              uuid                        DEFAULT public.gen_random_uuid() NOT NULL,
    stream_id       bigint                                                       NOT NULL,
    global_position bigserial                                                    NOT NULL,
    stream_revision integer                                                      NOT NULL,
    data            jsonb                       DEFAULT '{}'::jsonb              NOT NULL,
    metadata        jsonb                       DEFAULT '{}'::jsonb              NOT NULL,
    link_id         uuid,
    created_at      timestamp without time zone DEFAULT now()                    NOT NULL,
    event_type_id   bigint                                                       NOT NULL
);

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);

CREATE INDEX idx_events_event_type_id_and_global_position ON public.events USING btree (event_type_id, global_position);
CREATE INDEX idx_events_global_position ON public.events USING btree (global_position);
CREATE INDEX idx_events_link_id ON public.events USING btree (link_id);
CREATE INDEX idx_events_stream_id_and_revision ON public.events USING btree (stream_id, stream_revision);

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_stream_fk FOREIGN KEY (stream_id) REFERENCES public.streams (id) ON DELETE CASCADE;
ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_event_type_fk FOREIGN KEY (event_type_id) REFERENCES public.event_types (id);
ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_link_fk FOREIGN KEY (link_id) REFERENCES public.events (id) ON DELETE CASCADE;
