ALTER TABLE ONLY public.streams
    ADD CONSTRAINT streams_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_stream_fk FOREIGN KEY (stream_id)
        REFERENCES public.streams (id) ON DELETE CASCADE;
ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_link_fk FOREIGN KEY (link_id)
        REFERENCES public.events (id) ON DELETE CASCADE;
