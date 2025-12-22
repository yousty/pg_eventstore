--
-- PostgreSQL database dump
--

\restrict wsI9nLcucDpeBlVdv38oGhqwpgxpRGByZR4lLTShBrqUJES4jWNCUA4fNQtMZtL

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg12+2)
-- Dumped by pg_dump version 18.1 (Debian 18.1-1.pgdg12+2)

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
-- Name: nextval_with_xact_lock; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS nextval_with_xact_lock WITH SCHEMA public;


--
-- Name: EXTENSION nextval_with_xact_lock; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION nextval_with_xact_lock IS 'nextval_with_xact_lock:  Created by pgrx';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET default_tablespace = '';

--
-- Name: events; Type: TABLE; Schema: public; Owner: -
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
    link_id uuid,
    link_partition_id bigint,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    type character varying NOT NULL COLLATE pg_catalog."POSIX"
)
PARTITION BY LIST (context);


--
-- Name: $streams; Type: VIEW; Schema: public; Owner: -
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
    link_id,
    link_partition_id,
    created_at,
    type
   FROM public.events
  WHERE (stream_revision = 0);


--
-- Name: events_global_position_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_global_position_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_global_position_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_global_position_seq OWNED BY public.events.global_position;


SET default_table_access_method = heap;

--
-- Name: migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations (
    number integer NOT NULL
);


--
-- Name: partitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partitions (
    id bigint NOT NULL,
    context character varying NOT NULL COLLATE pg_catalog."POSIX",
    stream_name character varying COLLATE pg_catalog."POSIX",
    event_type character varying COLLATE pg_catalog."POSIX",
    table_name character varying NOT NULL COLLATE pg_catalog."POSIX"
);


--
-- Name: partitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.partitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: partitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.partitions_id_seq OWNED BY public.partitions.id;


--
-- Name: subscription_commands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_commands (
    id bigint NOT NULL,
    name character varying NOT NULL,
    subscription_id bigint NOT NULL,
    subscriptions_set_id bigint NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    data jsonb DEFAULT '{}'::jsonb
);


--
-- Name: subscription_commands_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscription_commands_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_commands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscription_commands_id_seq OWNED BY public.subscription_commands.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscriptions_id_seq OWNED BY public.subscriptions.id;


--
-- Name: subscriptions_set; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: subscriptions_set_commands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions_set_commands (
    id bigint NOT NULL,
    name character varying NOT NULL,
    subscriptions_set_id bigint NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    data jsonb DEFAULT '{}'::jsonb
);


--
-- Name: subscriptions_set_commands_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscriptions_set_commands_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_set_commands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscriptions_set_commands_id_seq OWNED BY public.subscriptions_set_commands.id;


--
-- Name: subscriptions_set_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscriptions_set_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_set_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscriptions_set_id_seq OWNED BY public.subscriptions_set.id;


--
-- Name: events global_position; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN global_position SET DEFAULT public.nextval_with_xact_lock(('public.events_global_position_seq'::regclass)::oid);


--
-- Name: partitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partitions ALTER COLUMN id SET DEFAULT nextval('public.partitions_id_seq'::regclass);


--
-- Name: subscription_commands id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_commands ALTER COLUMN id SET DEFAULT nextval('public.subscription_commands_id_seq'::regclass);


--
-- Name: subscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_id_seq'::regclass);


--
-- Name: subscriptions_set id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions_set ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_set_id_seq'::regclass);


--
-- Name: subscriptions_set_commands id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions_set_commands ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_set_commands_id_seq'::regclass);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (context, stream_name, type, global_position);


--
-- Name: partitions partitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partitions
    ADD CONSTRAINT partitions_pkey PRIMARY KEY (id);


--
-- Name: subscription_commands subscription_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_set_commands subscriptions_set_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions_set_commands
    ADD CONSTRAINT subscriptions_set_commands_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_set subscriptions_set_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions_set
    ADD CONSTRAINT subscriptions_set_pkey PRIMARY KEY (id);


--
-- Name: idx_events_0_stream_revision_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_0_stream_revision_global_position ON ONLY public.events USING btree (global_position) WHERE (stream_revision = 0);


--
-- Name: idx_events_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_global_position ON ONLY public.events USING btree (global_position);


--
-- Name: idx_events_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_id ON ONLY public.events USING btree (id);


--
-- Name: idx_events_link_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_link_id ON ONLY public.events USING btree (link_id);


--
-- Name: idx_events_stream_id_and_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_stream_id_and_global_position ON ONLY public.events USING btree (stream_id, global_position);


--
-- Name: idx_events_stream_id_and_stream_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_stream_id_and_stream_revision ON ONLY public.events USING btree (stream_id, stream_revision);


--
-- Name: idx_partitions_by_context; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_partitions_by_context ON public.partitions USING btree (context) WHERE ((stream_name IS NULL) AND (event_type IS NULL));


--
-- Name: idx_partitions_by_context_and_stream_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_partitions_by_context_and_stream_name ON public.partitions USING btree (context, stream_name) WHERE (event_type IS NULL);


--
-- Name: idx_partitions_by_context_and_stream_name_and_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_partitions_by_context_and_stream_name_and_event_type ON public.partitions USING btree (context, stream_name, event_type);


--
-- Name: idx_partitions_by_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partitions_by_event_type ON public.partitions USING btree (event_type);


--
-- Name: idx_partitions_by_partition_table_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_partitions_by_partition_table_name ON public.partitions USING btree (table_name);


--
-- Name: idx_subscr_set_commands_subscriptions_set_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_subscr_set_commands_subscriptions_set_id_and_name ON public.subscriptions_set_commands USING btree (subscriptions_set_id, name);


--
-- Name: idx_subscription_commands_subscription_id_and_set_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_subscription_commands_subscription_id_and_set_id_and_name ON public.subscription_commands USING btree (subscription_id, subscriptions_set_id, name);


--
-- Name: idx_subscriptions_locked_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subscriptions_locked_by ON public.subscriptions USING btree (locked_by);


--
-- Name: idx_subscriptions_set_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_subscriptions_set_and_name ON public.subscriptions USING btree (set, name);


--
-- Name: subscription_commands subscription_commands_subscription_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_subscription_fk FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id) ON DELETE CASCADE;


--
-- Name: subscription_commands subscription_commands_subscriptions_set_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_commands
    ADD CONSTRAINT subscription_commands_subscriptions_set_fk FOREIGN KEY (subscriptions_set_id) REFERENCES public.subscriptions_set(id) ON DELETE CASCADE;


--
-- Name: subscriptions_set_commands subscriptions_set_commands_subscriptions_set_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions_set_commands
    ADD CONSTRAINT subscriptions_set_commands_subscriptions_set_fk FOREIGN KEY (subscriptions_set_id) REFERENCES public.subscriptions_set(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_subscriptions_set_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_subscriptions_set_fk FOREIGN KEY (locked_by) REFERENCES public.subscriptions_set(id) ON DELETE SET NULL (locked_by);


--
-- PostgreSQL database dump complete
--

\unrestrict wsI9nLcucDpeBlVdv38oGhqwpgxpRGByZR4lLTShBrqUJES4jWNCUA4fNQtMZtL

