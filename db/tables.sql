CREATE TABLE public.streams
(
    id              bigserial         NOT NULL,
    context         character varying NOT NULL,
    stream_name     character varying NOT NULL,
    stream_id       character varying NOT NULL,
    stream_revision int DEFAULT -1    NOT NULL
);

CREATE TABLE public.events
(
    id              uuid                        NOT NULL DEFAULT public.gen_random_uuid(),
    stream_id       bigint                      NOT NULL,
    type            character varying           NOT NULL,
    global_position bigserial                   NOT NULL,
    stream_revision bigint                      NOT NULL,
    data            jsonb                       NOT NULL DEFAULT '{}'::jsonb,
    metadata        jsonb                       NOT NULL DEFAULT '{}'::jsonb,
    link_id         uuid,
    created_at      timestamp without time zone NOT NULL DEFAULT now()
);
