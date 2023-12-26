CREATE TABLE public.subscriptions
(
    id                           bigserial                   NOT NULL,
    set                          character varying           NOT NULL,
    name                         character varying           NOT NULL,
    options                      jsonb                                DEFAULT '{}'::jsonb,
    events_processed_total       bigint                               DEFAULT 0,
    current_position             bigint,
    events_processing_frequency  float4,
    state                        character varying,
    restarts_count               integer                              DEFAULT 0,
    last_restarted_at            timestamp without time zone,
    last_error                   jsonb,
    last_error_occurred_at       timestamp without time zone,
    chunk_query_interval         int2                        NOT NULL DEFAULT 5,
    last_chunk_fed_at            timestamp without time zone NOT NULL DEFAULT to_timestamp(0)::timestamp without time zone,
    last_chunk_greatest_position bigint,
    locked_by                    uuid,
    created_at                   timestamp without time zone NOT NULL DEFAULT now(),
    updated_at                   timestamp without time zone NOT NULL DEFAULT now()
);

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);

CREATE INDEX idx_subscriptions_set_and_name ON public.subscriptions USING btree (set, name);
