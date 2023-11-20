CREATE TABLE public.events
(
    id              uuid                        NOT NULL DEFAULT public.gen_random_uuid(),
    type            character varying,
    global_position bigserial                   NOT NULL,
    context         character varying           NOT NULL,
    stream_name     character varying           NOT NULL,
    stream_id       character varying           NOT NULL,
    stream_revision bigint                      NOT NULL,
    data            jsonb,
    metadata        jsonb,
    link_id         bigint,
    created_at      timestamp without time zone NOT NULL DEFAULT now()
);
