CREATE TABLE public.event_types
(
    id   bigserial                         NOT NULL,
    type character varying COLLATE "POSIX" NOT NULL
);

ALTER TABLE ONLY public.event_types
    ADD CONSTRAINT event_types_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_event_types_type ON public.event_types USING btree (type);
