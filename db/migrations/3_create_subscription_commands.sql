CREATE TABLE public.subscription_commands
(
    id                   bigserial                   NOT NULL,
    name                 character varying           NOT NULL,
    subscription_id      bigint                      NOT NULL,
    subscriptions_set_id bigint                      NOT NULL,
    created_at           timestamp without time zone NOT NULL DEFAULT now()
);

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_subscription_commands_subscription_id_and_set_id_and_name ON public.subscription_commands USING btree (subscription_id, subscriptions_set_id, name);

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_subscription_fk FOREIGN KEY (subscription_id) REFERENCES public.subscriptions (id) ON DELETE CASCADE;

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_subscriptions_set_fk FOREIGN KEY (subscriptions_set_id) REFERENCES public.subscriptions_set (id) ON DELETE CASCADE;
