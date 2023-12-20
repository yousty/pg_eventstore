CREATE TABLE public.event_types
(
    id              bigserial         NOT NULL,
    type            character varying NOT NULL
);

ALTER TABLE ONLY public.events ADD COLUMN event_type_id bigint;

ALTER TABLE ONLY public.event_types
    ADD CONSTRAINT event_types_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_event_type_fk FOREIGN KEY (event_type_id)
        REFERENCES public.event_types (id);

CREATE UNIQUE INDEX idx_event_types_type ON public.event_types USING btree (type);
CREATE INDEX idx_events_event_type_id ON public.events USING btree (event_type_id);
