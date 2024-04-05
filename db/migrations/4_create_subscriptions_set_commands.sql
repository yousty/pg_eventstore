CREATE TABLE public.subscriptions_set_commands
(
    id                   bigserial                   NOT NULL,
    name                 character varying           NOT NULL,
    subscriptions_set_id bigint                      NOT NULL,
    created_at           timestamp without time zone NOT NULL DEFAULT now()
);

ALTER TABLE ONLY public.subscriptions_set_commands
    ADD CONSTRAINT subscriptions_set_commands_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_subscr_set_commands_subscriptions_set_id_and_name ON public.subscriptions_set_commands USING btree (subscriptions_set_id, name);

ALTER TABLE ONLY public.subscriptions_set_commands
    ADD CONSTRAINT subscriptions_set_commands_subscriptions_set_fk FOREIGN KEY (subscriptions_set_id) REFERENCES public.subscriptions_set (id) ON DELETE CASCADE;
