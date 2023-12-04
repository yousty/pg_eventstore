CREATE TABLE public.streams
(
    id          bigserial         NOT NULL,
    context     character varying NOT NULL,
    stream_name character varying NOT NULL,
    stream_id   character varying NOT NULL
);

CREATE TABLE public.events
(
    id              uuid                        NOT NULL DEFAULT public.gen_random_uuid(),
    stream_id       bigint                      NOT NULL,
    type            character varying,
    global_position bigserial                   NOT NULL,
    stream_revision bigint                      NOT NULL,
    data            jsonb                       NOT NULL DEFAULT '{}'::jsonb,
    metadata        jsonb                       NOT NULL DEFAULT '{}'::jsonb,
    link_id         uuid,
    created_at      timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT must_have_either_type_or_be_a_link CHECK (NOT (type IS NULL AND link_id IS NULL))
);
