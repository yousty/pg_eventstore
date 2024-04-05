CREATE TABLE public.subscriptions_set
(
    id                     bigserial                   NOT NULL,
    name                   character varying           NOT NULL,
    state                  character varying           NOT NULL DEFAULT 'initial',
    restart_count          integer                     NOT NULL DEFAULT 0,
    max_restarts_number    int2                        NOT NULL DEFAULT 10,
    time_between_restarts  int2                        NOT NULL DEFAULT 1,
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
    id                            bigserial                   NOT NULL,
    set                           character varying           NOT NULL,
    name                          character varying           NOT NULL,
    options                       jsonb                       NOT NULL DEFAULT '{}'::jsonb,
    total_processed_events        bigint                      NOT NULL DEFAULT 0,
    current_position              bigint,
    average_event_processing_time float4,
    state                         character varying           NOT NULL DEFAULT 'initial',
    restart_count                 integer                     NOT NULL DEFAULT 0,
    max_restarts_number           int2                        NOT NULL DEFAULT 100,
    time_between_restarts         int2                        NOT NULL DEFAULT 1,
    last_restarted_at             timestamp without time zone,
    last_error                    jsonb,
    last_error_occurred_at        timestamp without time zone,
    chunk_query_interval          float4                      NOT NULL DEFAULT 1.0,
    last_chunk_fed_at             timestamp without time zone NOT NULL DEFAULT to_timestamp(0),
    last_chunk_greatest_position  bigint,
    locked_by                     bigint,
    created_at                    timestamp without time zone NOT NULL DEFAULT now(),
    updated_at                    timestamp without time zone NOT NULL DEFAULT now()
);

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_subscriptions_set_and_name ON public.subscriptions USING btree (set, name);
CREATE INDEX idx_subscriptions_locked_by ON public.subscriptions USING btree (locked_by);

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_subscriptions_set_fk FOREIGN KEY (locked_by) REFERENCES public.subscriptions_set (id) ON DELETE SET NULL (locked_by);
