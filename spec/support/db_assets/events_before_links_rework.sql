--
-- PostgreSQL database dump
--

\restrict YDhD9jKKgIgEQ0ExMldG0gsSC4a1b2GQHcsY39hiFoBpC4BTekVU03iyDOmLb2c

-- Dumped from database version 18.0 (Debian 18.0-1.pgdg13+3)
-- Dumped by pg_dump version 18.0 (Debian 18.0-1.pgdg13+3)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: log_events_horizon(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.log_events_horizon() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO events_horizon(global_position)
    VALUES (NEW.global_position);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_events_horizon() OWNER TO postgres;

SET default_tablespace = '';

--
-- Name: events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.events (
                               id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                               context character varying NOT NULL COLLATE pg_catalog."POSIX",
                               stream_name character varying NOT NULL COLLATE pg_catalog."POSIX",
                               stream_id character varying NOT NULL COLLATE pg_catalog."POSIX",
                               global_position bigint NOT NULL,
                               stream_revision integer NOT NULL,
                               data jsonb DEFAULT '{}'::jsonb NOT NULL,
                               metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
                               link_partition_id bigint,
                               created_at timestamp without time zone DEFAULT now() NOT NULL,
                               type character varying NOT NULL COLLATE pg_catalog."POSIX",
                               link_global_position bigint
)
    PARTITION BY LIST (context);


ALTER TABLE public.events OWNER TO postgres;

--
-- Name: $streams; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public."$streams" AS
SELECT id,
       context,
       stream_name,
       stream_id,
       global_position,
       stream_revision,
       data,
       metadata,
       link_partition_id,
       created_at,
       type,
       link_global_position
FROM public.events
WHERE (stream_revision = 0);


ALTER VIEW public."$streams" OWNER TO postgres;

--
-- Name: events_global_position_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.events_global_position_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.events_global_position_seq OWNER TO postgres;

--
-- Name: events_global_position_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.events_global_position_seq OWNED BY public.events.global_position;


--
-- Name: contexts_6879a3; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contexts_6879a3 (
                                        id uuid DEFAULT public.gen_random_uuid() CONSTRAINT events_id_not_null NOT NULL,
                                        context character varying CONSTRAINT events_context_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                        stream_name character varying CONSTRAINT events_stream_name_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                        stream_id character varying CONSTRAINT events_stream_id_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                        global_position bigint DEFAULT nextval('public.events_global_position_seq'::regclass) CONSTRAINT events_global_position_not_null NOT NULL,
                                        stream_revision integer CONSTRAINT events_stream_revision_not_null NOT NULL,
                                        data jsonb DEFAULT '{}'::jsonb CONSTRAINT events_data_not_null NOT NULL,
                                        metadata jsonb DEFAULT '{}'::jsonb CONSTRAINT events_metadata_not_null NOT NULL,
                                        link_partition_id bigint,
                                        created_at timestamp without time zone DEFAULT now() CONSTRAINT events_created_at_not_null NOT NULL,
                                        type character varying CONSTRAINT events_type_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                        link_global_position bigint
)
    PARTITION BY LIST (stream_name);


ALTER TABLE public.contexts_6879a3 OWNER TO postgres;

--
-- Name: stream_names_5109b5; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stream_names_5109b5 (
                                            id uuid DEFAULT public.gen_random_uuid() CONSTRAINT events_id_not_null NOT NULL,
                                            context character varying CONSTRAINT events_context_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                            stream_name character varying CONSTRAINT events_stream_name_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                            stream_id character varying CONSTRAINT events_stream_id_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                            global_position bigint DEFAULT nextval('public.events_global_position_seq'::regclass) CONSTRAINT events_global_position_not_null NOT NULL,
                                            stream_revision integer CONSTRAINT events_stream_revision_not_null NOT NULL,
                                            data jsonb DEFAULT '{}'::jsonb CONSTRAINT events_data_not_null NOT NULL,
                                            metadata jsonb DEFAULT '{}'::jsonb CONSTRAINT events_metadata_not_null NOT NULL,
                                            link_partition_id bigint,
                                            created_at timestamp without time zone DEFAULT now() CONSTRAINT events_created_at_not_null NOT NULL,
                                            type character varying CONSTRAINT events_type_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                            link_global_position bigint
)
    PARTITION BY LIST (type);


ALTER TABLE public.stream_names_5109b5 OWNER TO postgres;

SET default_table_access_method = heap;

--
-- Name: event_types_5d3abb; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.event_types_5d3abb (
                                           id uuid DEFAULT public.gen_random_uuid() CONSTRAINT events_id_not_null NOT NULL,
                                           context character varying CONSTRAINT events_context_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                           stream_name character varying CONSTRAINT events_stream_name_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                           stream_id character varying CONSTRAINT events_stream_id_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                           global_position bigint DEFAULT nextval('public.events_global_position_seq'::regclass) CONSTRAINT events_global_position_not_null NOT NULL,
                                           stream_revision integer CONSTRAINT events_stream_revision_not_null NOT NULL,
                                           data jsonb DEFAULT '{}'::jsonb CONSTRAINT events_data_not_null NOT NULL,
                                           metadata jsonb DEFAULT '{}'::jsonb CONSTRAINT events_metadata_not_null NOT NULL,
                                           link_partition_id bigint,
                                           created_at timestamp without time zone DEFAULT now() CONSTRAINT events_created_at_not_null NOT NULL,
                                           type character varying CONSTRAINT events_type_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                           link_global_position bigint
);


ALTER TABLE public.event_types_5d3abb OWNER TO postgres;

--
-- Name: stream_names_db8e87; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stream_names_db8e87 (
                                            id uuid DEFAULT public.gen_random_uuid() CONSTRAINT events_id_not_null NOT NULL,
                                            context character varying CONSTRAINT events_context_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                            stream_name character varying CONSTRAINT events_stream_name_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                            stream_id character varying CONSTRAINT events_stream_id_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                            global_position bigint DEFAULT nextval('public.events_global_position_seq'::regclass) CONSTRAINT events_global_position_not_null NOT NULL,
                                            stream_revision integer CONSTRAINT events_stream_revision_not_null NOT NULL,
                                            data jsonb DEFAULT '{}'::jsonb CONSTRAINT events_data_not_null NOT NULL,
                                            metadata jsonb DEFAULT '{}'::jsonb CONSTRAINT events_metadata_not_null NOT NULL,
                                            link_partition_id bigint,
                                            created_at timestamp without time zone DEFAULT now() CONSTRAINT events_created_at_not_null NOT NULL,
                                            type character varying CONSTRAINT events_type_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                            link_global_position bigint
)
    PARTITION BY LIST (type);


ALTER TABLE public.stream_names_db8e87 OWNER TO postgres;

--
-- Name: event_types_a32711; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.event_types_a32711 (
                                           id uuid DEFAULT public.gen_random_uuid() CONSTRAINT events_id_not_null NOT NULL,
                                           context character varying CONSTRAINT events_context_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                           stream_name character varying CONSTRAINT events_stream_name_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                           stream_id character varying CONSTRAINT events_stream_id_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                           global_position bigint DEFAULT nextval('public.events_global_position_seq'::regclass) CONSTRAINT events_global_position_not_null NOT NULL,
                                           stream_revision integer CONSTRAINT events_stream_revision_not_null NOT NULL,
                                           data jsonb DEFAULT '{}'::jsonb CONSTRAINT events_data_not_null NOT NULL,
                                           metadata jsonb DEFAULT '{}'::jsonb CONSTRAINT events_metadata_not_null NOT NULL,
                                           link_partition_id bigint,
                                           created_at timestamp without time zone DEFAULT now() CONSTRAINT events_created_at_not_null NOT NULL,
                                           type character varying CONSTRAINT events_type_not_null NOT NULL COLLATE pg_catalog."POSIX",
                                           link_global_position bigint
);


ALTER TABLE public.event_types_a32711 OWNER TO postgres;

--
-- Name: events_horizon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE UNLOGGED TABLE public.events_horizon (
                                                global_position bigint NOT NULL,
                                                xact_id xid8 DEFAULT pg_current_xact_id() NOT NULL
);


ALTER TABLE public.events_horizon OWNER TO postgres;

--
-- Name: TABLE events_horizon; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.events_horizon IS 'Internal use only. Data is limited to the PostgreSQL cluster in which it was created. DO NOT INCLUDE ITS DATA INTO YOUR DUMP.';


--
-- Name: migrations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.migrations (
                                   number integer NOT NULL
);


ALTER TABLE public.migrations OWNER TO postgres;

--
-- Name: partitions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partitions (
                                   id bigint NOT NULL,
                                   context character varying NOT NULL COLLATE pg_catalog."POSIX",
                                   stream_name character varying COLLATE pg_catalog."POSIX",
                                   event_type character varying COLLATE pg_catalog."POSIX",
                                   table_name character varying NOT NULL COLLATE pg_catalog."POSIX"
);


ALTER TABLE public.partitions OWNER TO postgres;

--
-- Name: partitions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.partitions_id_seq OWNER TO postgres;

--
-- Name: partitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.partitions_id_seq OWNED BY public.partitions.id;


--
-- Name: subscription_commands; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subscription_commands (
                                              id bigint NOT NULL,
                                              name character varying NOT NULL,
                                              subscription_id bigint NOT NULL,
                                              subscriptions_set_id bigint NOT NULL,
                                              created_at timestamp without time zone DEFAULT now() NOT NULL,
                                              data jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.subscription_commands OWNER TO postgres;

--
-- Name: subscription_commands_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subscription_commands_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subscription_commands_id_seq OWNER TO postgres;

--
-- Name: subscription_commands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subscription_commands_id_seq OWNED BY public.subscription_commands.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subscriptions (
                                      id bigint NOT NULL,
                                      set character varying NOT NULL,
                                      name character varying NOT NULL,
                                      options jsonb DEFAULT '{}'::jsonb NOT NULL,
                                      total_processed_events bigint DEFAULT 0 NOT NULL,
                                      current_position bigint,
                                      average_event_processing_time real,
                                      state character varying DEFAULT 'initial'::character varying NOT NULL,
                                      restart_count integer DEFAULT 0 NOT NULL,
                                      max_restarts_number smallint DEFAULT 100 NOT NULL,
                                      time_between_restarts smallint DEFAULT 1 NOT NULL,
                                      last_restarted_at timestamp without time zone,
                                      last_error jsonb,
                                      last_error_occurred_at timestamp without time zone,
                                      chunk_query_interval real DEFAULT 1.0 NOT NULL,
                                      last_chunk_fed_at timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
                                      last_chunk_greatest_position bigint,
                                      locked_by bigint,
                                      created_at timestamp without time zone DEFAULT now() NOT NULL,
                                      updated_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.subscriptions OWNER TO postgres;

--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subscriptions_id_seq OWNER TO postgres;

--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subscriptions_id_seq OWNED BY public.subscriptions.id;


--
-- Name: subscriptions_set; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subscriptions_set (
                                          id bigint NOT NULL,
                                          name character varying NOT NULL,
                                          state character varying DEFAULT 'initial'::character varying NOT NULL,
                                          restart_count integer DEFAULT 0 NOT NULL,
                                          max_restarts_number smallint DEFAULT 10 NOT NULL,
                                          time_between_restarts smallint DEFAULT 1 NOT NULL,
                                          last_restarted_at timestamp without time zone,
                                          last_error jsonb,
                                          last_error_occurred_at timestamp without time zone,
                                          created_at timestamp without time zone DEFAULT now() NOT NULL,
                                          updated_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.subscriptions_set OWNER TO postgres;

--
-- Name: subscriptions_set_commands; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subscriptions_set_commands (
                                                   id bigint NOT NULL,
                                                   name character varying NOT NULL,
                                                   subscriptions_set_id bigint NOT NULL,
                                                   created_at timestamp without time zone DEFAULT now() NOT NULL,
                                                   data jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.subscriptions_set_commands OWNER TO postgres;

--
-- Name: subscriptions_set_commands_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subscriptions_set_commands_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subscriptions_set_commands_id_seq OWNER TO postgres;

--
-- Name: subscriptions_set_commands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subscriptions_set_commands_id_seq OWNED BY public.subscriptions_set_commands.id;


--
-- Name: subscriptions_set_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subscriptions_set_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subscriptions_set_id_seq OWNER TO postgres;

--
-- Name: subscriptions_set_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subscriptions_set_id_seq OWNED BY public.subscriptions_set.id;


--
-- Name: contexts_6879a3; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.events ATTACH PARTITION public.contexts_6879a3 FOR VALUES IN ('FooCtx');


--
-- Name: event_types_5d3abb; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stream_names_5109b5 ATTACH PARTITION public.event_types_5d3abb FOR VALUES IN ('$>');


--
-- Name: event_types_a32711; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stream_names_db8e87 ATTACH PARTITION public.event_types_a32711 FOR VALUES IN ('Foo');


--
-- Name: stream_names_5109b5; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contexts_6879a3 ATTACH PARTITION public.stream_names_5109b5 FOR VALUES IN ('BarProjection');


--
-- Name: stream_names_db8e87; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contexts_6879a3 ATTACH PARTITION public.stream_names_db8e87 FOR VALUES IN ('Bar');


--
-- Name: events global_position; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.events ALTER COLUMN global_position SET DEFAULT nextval('public.events_global_position_seq'::regclass);


--
-- Name: partitions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partitions ALTER COLUMN id SET DEFAULT nextval('public.partitions_id_seq'::regclass);


--
-- Name: subscription_commands id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_commands ALTER COLUMN id SET DEFAULT nextval('public.subscription_commands_id_seq'::regclass);


--
-- Name: subscriptions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_id_seq'::regclass);


--
-- Name: subscriptions_set id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions_set ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_set_id_seq'::regclass);


--
-- Name: subscriptions_set_commands id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions_set_commands ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_set_commands_id_seq'::regclass);


--
-- Data for Name: event_types_5d3abb; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.event_types_5d3abb (id, context, stream_name, stream_id, global_position, stream_revision, data, metadata, link_partition_id, created_at, type, link_global_position) FROM stdin;
25d31190-f665-4866-afdf-e200fefe9c18	FooCtx	BarProjection	1	3	0	{}	{}	3	2026-01-12 21:28:54.102308	$>	1
18265c54-0627-484f-88c7-7c53679881a9	FooCtx	BarProjection	1	4	1	{}	{}	3	2026-01-12 21:28:54.102308	$>	2
\.


--
-- Data for Name: event_types_a32711; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.event_types_a32711 (id, context, stream_name, stream_id, global_position, stream_revision, data, metadata, link_partition_id, created_at, type, link_global_position) FROM stdin;
da0b7cae-b04a-414b-aea3-58a985709947	FooCtx	Bar	1	1	0	{"foo": "foo"}	{}	\N	2026-01-12 21:28:54.081387	Foo	\N
d14ee952-cb7b-4d09-b9ce-a53accdb7c55	FooCtx	Bar	2	2	0	{"foo": "bar"}	{}	\N	2026-01-12 21:28:54.08657	Foo	\N
\.


--
-- Data for Name: migrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.migrations (number) FROM stdin;
0
1
2
3
4
5
6
7
8
9
10
11
12
13
14
\.


--
-- Data for Name: partitions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.partitions (id, context, stream_name, event_type, table_name) FROM stdin;
1	FooCtx	\N	\N	contexts_6879a3
2	FooCtx	Bar	\N	stream_names_db8e87
3	FooCtx	Bar	Foo	event_types_a32711
4	FooCtx	BarProjection	\N	stream_names_5109b5
5	FooCtx	BarProjection	$>	event_types_5d3abb
\.


--
-- Data for Name: subscription_commands; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.subscription_commands (id, name, subscription_id, subscriptions_set_id, created_at, data) FROM stdin;
\.


--
-- Data for Name: subscriptions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.subscriptions (id, set, name, options, total_processed_events, current_position, average_event_processing_time, state, restart_count, max_restarts_number, time_between_restarts, last_restarted_at, last_error, last_error_occurred_at, chunk_query_interval, last_chunk_fed_at, last_chunk_greatest_position, locked_by, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: subscriptions_set; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.subscriptions_set (id, name, state, restart_count, max_restarts_number, time_between_restarts, last_restarted_at, last_error, last_error_occurred_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: subscriptions_set_commands; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.subscriptions_set_commands (id, name, subscriptions_set_id, created_at, data) FROM stdin;
\.


--
-- Name: events_global_position_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.events_global_position_seq', 4, true);


--
-- Name: partitions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.partitions_id_seq', 5, true);


--
-- Name: subscription_commands_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subscription_commands_id_seq', 1, false);


--
-- Name: subscriptions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subscriptions_id_seq', 1, false);


--
-- Name: subscriptions_set_commands_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subscriptions_set_commands_id_seq', 1, false);


--
-- Name: subscriptions_set_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subscriptions_set_id_seq', 1, false);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (context, stream_name, type, global_position);


--
-- Name: contexts_6879a3 contexts_6879a3_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contexts_6879a3
    ADD CONSTRAINT contexts_6879a3_pkey PRIMARY KEY (context, stream_name, type, global_position);


--
-- Name: stream_names_5109b5 stream_names_5109b5_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stream_names_5109b5
    ADD CONSTRAINT stream_names_5109b5_pkey PRIMARY KEY (context, stream_name, type, global_position);


--
-- Name: event_types_5d3abb event_types_5d3abb_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event_types_5d3abb
    ADD CONSTRAINT event_types_5d3abb_pkey PRIMARY KEY (context, stream_name, type, global_position);


--
-- Name: stream_names_db8e87 stream_names_db8e87_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stream_names_db8e87
    ADD CONSTRAINT stream_names_db8e87_pkey PRIMARY KEY (context, stream_name, type, global_position);


--
-- Name: event_types_a32711 event_types_a32711_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event_types_a32711
    ADD CONSTRAINT event_types_a32711_pkey PRIMARY KEY (context, stream_name, type, global_position);


--
-- Name: partitions partitions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partitions
    ADD CONSTRAINT partitions_pkey PRIMARY KEY (id);


--
-- Name: subscription_commands subscription_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_set_commands subscriptions_set_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions_set_commands
    ADD CONSTRAINT subscriptions_set_commands_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_set subscriptions_set_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions_set
    ADD CONSTRAINT subscriptions_set_pkey PRIMARY KEY (id);


--
-- Name: idx_events_global_position; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_events_global_position ON ONLY public.events USING btree (global_position);


--
-- Name: contexts_6879a3_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX contexts_6879a3_global_position_idx ON ONLY public.contexts_6879a3 USING btree (global_position);


--
-- Name: idx_events_0_stream_revision_global_position; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_events_0_stream_revision_global_position ON ONLY public.events USING btree (global_position) WHERE (stream_revision = 0);


--
-- Name: contexts_6879a3_global_position_idx1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX contexts_6879a3_global_position_idx1 ON ONLY public.contexts_6879a3 USING btree (global_position) WHERE (stream_revision = 0);


--
-- Name: idx_events_stream_id_and_global_position; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_events_stream_id_and_global_position ON ONLY public.events USING btree (stream_id, global_position);


--
-- Name: contexts_6879a3_stream_id_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX contexts_6879a3_stream_id_global_position_idx ON ONLY public.contexts_6879a3 USING btree (stream_id, global_position);


--
-- Name: idx_events_stream_id_and_stream_revision; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_events_stream_id_and_stream_revision ON ONLY public.events USING btree (stream_id, stream_revision);


--
-- Name: contexts_6879a3_stream_id_stream_revision_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX contexts_6879a3_stream_id_stream_revision_idx ON ONLY public.contexts_6879a3 USING btree (stream_id, stream_revision);


--
-- Name: stream_names_5109b5_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stream_names_5109b5_global_position_idx ON ONLY public.stream_names_5109b5 USING btree (global_position);


--
-- Name: event_types_5d3abb_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX event_types_5d3abb_global_position_idx ON public.event_types_5d3abb USING btree (global_position);


--
-- Name: stream_names_5109b5_global_position_idx1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stream_names_5109b5_global_position_idx1 ON ONLY public.stream_names_5109b5 USING btree (global_position) WHERE (stream_revision = 0);


--
-- Name: event_types_5d3abb_global_position_idx1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX event_types_5d3abb_global_position_idx1 ON public.event_types_5d3abb USING btree (global_position) WHERE (stream_revision = 0);


--
-- Name: stream_names_5109b5_stream_id_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stream_names_5109b5_stream_id_global_position_idx ON ONLY public.stream_names_5109b5 USING btree (stream_id, global_position);


--
-- Name: event_types_5d3abb_stream_id_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX event_types_5d3abb_stream_id_global_position_idx ON public.event_types_5d3abb USING btree (stream_id, global_position);


--
-- Name: stream_names_5109b5_stream_id_stream_revision_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stream_names_5109b5_stream_id_stream_revision_idx ON ONLY public.stream_names_5109b5 USING btree (stream_id, stream_revision);


--
-- Name: event_types_5d3abb_stream_id_stream_revision_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX event_types_5d3abb_stream_id_stream_revision_idx ON public.event_types_5d3abb USING btree (stream_id, stream_revision);


--
-- Name: stream_names_db8e87_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stream_names_db8e87_global_position_idx ON ONLY public.stream_names_db8e87 USING btree (global_position);


--
-- Name: event_types_a32711_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX event_types_a32711_global_position_idx ON public.event_types_a32711 USING btree (global_position);


--
-- Name: stream_names_db8e87_global_position_idx1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stream_names_db8e87_global_position_idx1 ON ONLY public.stream_names_db8e87 USING btree (global_position) WHERE (stream_revision = 0);


--
-- Name: event_types_a32711_global_position_idx1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX event_types_a32711_global_position_idx1 ON public.event_types_a32711 USING btree (global_position) WHERE (stream_revision = 0);


--
-- Name: stream_names_db8e87_stream_id_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stream_names_db8e87_stream_id_global_position_idx ON ONLY public.stream_names_db8e87 USING btree (stream_id, global_position);


--
-- Name: event_types_a32711_stream_id_global_position_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX event_types_a32711_stream_id_global_position_idx ON public.event_types_a32711 USING btree (stream_id, global_position);


--
-- Name: stream_names_db8e87_stream_id_stream_revision_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stream_names_db8e87_stream_id_stream_revision_idx ON ONLY public.stream_names_db8e87 USING btree (stream_id, stream_revision);


--
-- Name: event_types_a32711_stream_id_stream_revision_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX event_types_a32711_stream_id_stream_revision_idx ON public.event_types_a32711 USING btree (stream_id, stream_revision);


--
-- Name: idx_partitions_by_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_partitions_by_context ON public.partitions USING btree (context) WHERE ((stream_name IS NULL) AND (event_type IS NULL));


--
-- Name: idx_partitions_by_context_and_stream_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_partitions_by_context_and_stream_name ON public.partitions USING btree (context, stream_name) WHERE (event_type IS NULL);


--
-- Name: idx_partitions_by_context_and_stream_name_and_event_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_partitions_by_context_and_stream_name_and_event_type ON public.partitions USING btree (context, stream_name, event_type);


--
-- Name: idx_partitions_by_event_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_partitions_by_event_type ON public.partitions USING btree (event_type);


--
-- Name: idx_partitions_by_partition_table_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_partitions_by_partition_table_name ON public.partitions USING btree (table_name);


--
-- Name: idx_subscr_set_commands_subscriptions_set_id_and_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_subscr_set_commands_subscriptions_set_id_and_name ON public.subscriptions_set_commands USING btree (subscriptions_set_id, name);


--
-- Name: idx_subscription_commands_subscription_id_and_set_id_and_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_subscription_commands_subscription_id_and_set_id_and_name ON public.subscription_commands USING btree (subscription_id, subscriptions_set_id, name);


--
-- Name: idx_subscriptions_locked_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_subscriptions_locked_by ON public.subscriptions USING btree (locked_by);


--
-- Name: idx_subscriptions_set_and_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_subscriptions_set_and_name ON public.subscriptions USING btree (set, name);


--
-- Name: idx_xact_id_and_created_at_and_global_position; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_xact_id_and_created_at_and_global_position ON public.events_horizon USING btree (xact_id, global_position);


--
-- Name: contexts_6879a3_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.idx_events_global_position ATTACH PARTITION public.contexts_6879a3_global_position_idx;


--
-- Name: contexts_6879a3_global_position_idx1; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.idx_events_0_stream_revision_global_position ATTACH PARTITION public.contexts_6879a3_global_position_idx1;


--
-- Name: contexts_6879a3_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.events_pkey ATTACH PARTITION public.contexts_6879a3_pkey;


--
-- Name: contexts_6879a3_stream_id_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.idx_events_stream_id_and_global_position ATTACH PARTITION public.contexts_6879a3_stream_id_global_position_idx;


--
-- Name: contexts_6879a3_stream_id_stream_revision_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.idx_events_stream_id_and_stream_revision ATTACH PARTITION public.contexts_6879a3_stream_id_stream_revision_idx;


--
-- Name: event_types_5d3abb_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_5109b5_global_position_idx ATTACH PARTITION public.event_types_5d3abb_global_position_idx;


--
-- Name: event_types_5d3abb_global_position_idx1; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_5109b5_global_position_idx1 ATTACH PARTITION public.event_types_5d3abb_global_position_idx1;


--
-- Name: event_types_5d3abb_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_5109b5_pkey ATTACH PARTITION public.event_types_5d3abb_pkey;


--
-- Name: event_types_5d3abb_stream_id_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_5109b5_stream_id_global_position_idx ATTACH PARTITION public.event_types_5d3abb_stream_id_global_position_idx;


--
-- Name: event_types_5d3abb_stream_id_stream_revision_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_5109b5_stream_id_stream_revision_idx ATTACH PARTITION public.event_types_5d3abb_stream_id_stream_revision_idx;


--
-- Name: event_types_a32711_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_db8e87_global_position_idx ATTACH PARTITION public.event_types_a32711_global_position_idx;


--
-- Name: event_types_a32711_global_position_idx1; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_db8e87_global_position_idx1 ATTACH PARTITION public.event_types_a32711_global_position_idx1;


--
-- Name: event_types_a32711_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_db8e87_pkey ATTACH PARTITION public.event_types_a32711_pkey;


--
-- Name: event_types_a32711_stream_id_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_db8e87_stream_id_global_position_idx ATTACH PARTITION public.event_types_a32711_stream_id_global_position_idx;


--
-- Name: event_types_a32711_stream_id_stream_revision_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.stream_names_db8e87_stream_id_stream_revision_idx ATTACH PARTITION public.event_types_a32711_stream_id_stream_revision_idx;


--
-- Name: stream_names_5109b5_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_global_position_idx ATTACH PARTITION public.stream_names_5109b5_global_position_idx;


--
-- Name: stream_names_5109b5_global_position_idx1; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_global_position_idx1 ATTACH PARTITION public.stream_names_5109b5_global_position_idx1;


--
-- Name: stream_names_5109b5_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_pkey ATTACH PARTITION public.stream_names_5109b5_pkey;


--
-- Name: stream_names_5109b5_stream_id_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_stream_id_global_position_idx ATTACH PARTITION public.stream_names_5109b5_stream_id_global_position_idx;


--
-- Name: stream_names_5109b5_stream_id_stream_revision_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_stream_id_stream_revision_idx ATTACH PARTITION public.stream_names_5109b5_stream_id_stream_revision_idx;


--
-- Name: stream_names_db8e87_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_global_position_idx ATTACH PARTITION public.stream_names_db8e87_global_position_idx;


--
-- Name: stream_names_db8e87_global_position_idx1; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_global_position_idx1 ATTACH PARTITION public.stream_names_db8e87_global_position_idx1;


--
-- Name: stream_names_db8e87_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_pkey ATTACH PARTITION public.stream_names_db8e87_pkey;


--
-- Name: stream_names_db8e87_stream_id_global_position_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_stream_id_global_position_idx ATTACH PARTITION public.stream_names_db8e87_stream_id_global_position_idx;


--
-- Name: stream_names_db8e87_stream_id_stream_revision_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.contexts_6879a3_stream_id_stream_revision_idx ATTACH PARTITION public.stream_names_db8e87_stream_id_stream_revision_idx;


--
-- Name: events log_events_horizon; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER log_events_horizon AFTER INSERT ON public.events FOR EACH ROW EXECUTE FUNCTION public.log_events_horizon();


--
-- Name: subscription_commands subscription_commands_subscription_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_subscription_fk FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id) ON DELETE CASCADE;


--
-- Name: subscription_commands subscription_commands_subscriptions_set_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_subscriptions_set_fk FOREIGN KEY (subscriptions_set_id) REFERENCES public.subscriptions_set(id) ON DELETE CASCADE;


--
-- Name: subscriptions_set_commands subscriptions_set_commands_subscriptions_set_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions_set_commands
    ADD CONSTRAINT subscriptions_set_commands_subscriptions_set_fk FOREIGN KEY (subscriptions_set_id) REFERENCES public.subscriptions_set(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_subscriptions_set_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_subscriptions_set_fk FOREIGN KEY (locked_by) REFERENCES public.subscriptions_set(id) ON DELETE SET NULL (locked_by);


--
-- PostgreSQL database dump complete
--

\unrestrict YDhD9jKKgIgEQ0ExMldG0gsSC4a1b2GQHcsY39hiFoBpC4BTekVU03iyDOmLb2c

