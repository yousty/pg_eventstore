CREATE TABLE public.subscriptions_set
(
    id                     uuid                                 DEFAULT public.gen_random_uuid() NOT NULL,
    name                   character varying           NOT NULL,
    state                  character varying           NOT NULL DEFAULT 'initial',
    restarts_count         integer                     NOT NULL DEFAULT 0,
    max_restarts_number    int2                        NOT NULL DEFAULT 10,
    last_restarted_at      timestamp without time zone,
    last_error             jsonb,
    last_error_occurred_at timestamp without time zone,
    created_at             timestamp without time zone NOT NULL DEFAULT now(),
    updated_at             timestamp without time zone NOT NULL DEFAULT now()
);

ALTER TABLE ONLY public.subscriptions_set
    ADD CONSTRAINT subscriptions_set_pkey PRIMARY KEY (id);

CREATE TABLE public.subscriptions
(
    id                           bigserial                   NOT NULL,
    set                          character varying           NOT NULL,
    name                         character varying           NOT NULL,
    options                      jsonb                       NOT NULL DEFAULT '{}'::jsonb,
    events_processed_total       bigint                      NOT NULL DEFAULT 0,
    current_position             bigint,
    events_processing_frequency  float4,
    state                        character varying           NOT NULL DEFAULT 'initial',
    restarts_count               integer                     NOT NULL DEFAULT 0,
    max_restarts_number          int2                        NOT NULL DEFAULT 100,
    last_restarted_at            timestamp without time zone,
    last_error                   jsonb,
    last_error_occurred_at       timestamp without time zone,
    chunk_query_interval         int2                        NOT NULL DEFAULT 5,
    last_chunk_fed_at            timestamp without time zone NOT NULL DEFAULT to_timestamp(0),
    last_chunk_greatest_position bigint,
    locked_by                    uuid,
    created_at                   timestamp without time zone NOT NULL DEFAULT now(),
    updated_at                   timestamp without time zone NOT NULL DEFAULT now()
);

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);

CREATE INDEX idx_subscriptions_set_and_name ON public.subscriptions USING btree (set, name);
