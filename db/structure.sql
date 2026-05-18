--
-- PostgreSQL database dump
--

\restrict rz4wOyDTt9VVXaJfTLbHn0Pgweo1TtH3wrphMefdURhNKxAI3O4w9u7TfVYHfeY

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


--
-- Name: log_events_horizon(); Type: FUNCTION; Schema: public; Owner: -
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
    stream_revision bigint NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    link_partition_id bigint,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    type character varying NOT NULL COLLATE pg_catalog."POSIX",
    link_global_position bigint
)
PARTITION BY LIST (context);


SET default_table_access_method = heap;

--
-- Name: events_global_index; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events_global_index (
    global_position bigint NOT NULL,
    stream_revision bigint NOT NULL,
    context_partition_id bigint NOT NULL,
    stream_name_partition_id bigint NOT NULL,
    event_type_partition_id bigint NOT NULL,
    streams_global_index_id bigint NOT NULL
);


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


--
-- Name: events_horizon; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.events_horizon (
    global_position bigint NOT NULL,
    xact_id xid8 DEFAULT pg_current_xact_id() NOT NULL
);


--
-- Name: TABLE events_horizon; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.events_horizon IS 'Internal use only. Data is limited to the PostgreSQL cluster in which it was created. DO NOT INCLUDE ITS DATA INTO YOUR DUMP.';


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
    table_name character varying NOT NULL COLLATE pg_catalog."POSIX",
    parent_stream_name_partition_id bigint,
    parent_context_partition_id bigint
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
-- Name: streams_global_index; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.streams_global_index (
    id bigint NOT NULL,
    partition_id bigint NOT NULL,
    stream_id character varying NOT NULL COLLATE pg_catalog."POSIX",
    stream_revision bigint NOT NULL,
    starting_position bigint NOT NULL
);


--
-- Name: streams_global_index_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.streams_global_index_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: streams_global_index_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.streams_global_index_id_seq OWNED BY public.streams_global_index.id;


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

ALTER TABLE ONLY public.events ALTER COLUMN global_position SET DEFAULT nextval('public.events_global_position_seq'::regclass);


--
-- Name: partitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partitions ALTER COLUMN id SET DEFAULT nextval('public.partitions_id_seq'::regclass);


--
-- Name: streams_global_index id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streams_global_index ALTER COLUMN id SET DEFAULT nextval('public.streams_global_index_id_seq'::regclass);


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
-- Name: partitions partitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partitions
    ADD CONSTRAINT partitions_pkey PRIMARY KEY (id);


--
-- Name: streams_global_index streams_global_index_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streams_global_index
    ADD CONSTRAINT streams_global_index_pkey PRIMARY KEY (id);


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
-- Name: idx_events_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_global_position ON ONLY public.events USING btree (global_position);


--
-- Name: idx_events_idx_on_ctx_part_id_n_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_idx_on_ctx_part_id_n_position ON public.events_global_index USING btree (context_partition_id, global_position);


--
-- Name: idx_events_idx_on_e_type_part_id_n_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_idx_on_e_type_part_id_n_position ON public.events_global_index USING btree (event_type_partition_id, global_position);


--
-- Name: idx_events_idx_on_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_idx_on_global_position ON public.events_global_index USING btree (global_position);


--
-- Name: idx_events_idx_on_stream_name_part_id_n_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_idx_on_stream_name_part_id_n_position ON public.events_global_index USING btree (stream_name_partition_id, global_position);


--
-- Name: idx_events_idx_on_streams_idx_id_n_e_type_part_id_n_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_idx_on_streams_idx_id_n_e_type_part_id_n_position ON public.events_global_index USING btree (streams_global_index_id, event_type_partition_id, global_position);


--
-- Name: idx_events_idx_on_streams_idx_id_n_e_type_part_id_n_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_idx_on_streams_idx_id_n_e_type_part_id_n_revision ON public.events_global_index USING btree (streams_global_index_id, event_type_partition_id, stream_revision);


--
-- Name: idx_events_idx_on_streams_idx_id_n_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_idx_on_streams_idx_id_n_position ON public.events_global_index USING btree (streams_global_index_id, global_position);


--
-- Name: idx_events_idx_on_streams_idx_id_n_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_idx_on_streams_idx_id_n_revision ON public.events_global_index USING btree (streams_global_index_id, stream_revision);


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
-- Name: idx_partitions_by_context_and_stream_name_and_event_type_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partitions_by_context_and_stream_name_and_event_type_and_id ON public.partitions USING btree (context, stream_name, event_type, id);


--
-- Name: idx_partitions_by_event_type_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partitions_by_event_type_and_id ON public.partitions USING btree (event_type, id);


--
-- Name: idx_partitions_by_partition_table_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_partitions_by_partition_table_name ON public.partitions USING btree (table_name);


--
-- Name: idx_streams_global_index_on_starting_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_streams_global_index_on_starting_position ON public.streams_global_index USING btree (starting_position);


--
-- Name: idx_streams_global_index_on_stream_id_and_partition_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_streams_global_index_on_stream_id_and_partition_id ON public.streams_global_index USING btree (stream_id, partition_id);


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
-- Name: idx_xact_id_and_created_at_and_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_xact_id_and_created_at_and_global_position ON public.events_horizon USING btree (xact_id, global_position);


--
-- Name: partition_parts_dep; Type: STATISTICS; Schema: public; Owner: -
--

CREATE STATISTICS public.partition_parts_dep (dependencies) ON context, stream_name, event_type FROM public.partitions;


--
-- Name: events log_events_horizon; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER log_events_horizon AFTER INSERT ON public.events FOR EACH ROW EXECUTE FUNCTION public.log_events_horizon();


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

\unrestrict rz4wOyDTt9VVXaJfTLbHn0Pgweo1TtH3wrphMefdURhNKxAI3O4w9u7TfVYHfeY

