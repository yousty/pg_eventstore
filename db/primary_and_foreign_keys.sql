ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (global_position);
ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_link_fk FOREIGN KEY (link_id)
        REFERENCES public.events (global_position) ON DELETE CASCADE;
