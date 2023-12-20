--
-- PostgreSQL database dump
--

-- Dumped from database version 16.0 (Debian 16.0-1.pgdg120+1)
-- Dumped by pg_dump version 16.0 (Debian 16.0-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: event_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_types (
    id bigint NOT NULL,
    type character varying NOT NULL
);


--
-- Name: event_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.event_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: event_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.event_types_id_seq OWNED BY public.event_types.id;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    stream_id bigint NOT NULL,
    global_position bigint NOT NULL,
    stream_revision integer NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    link_id uuid,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    event_type_id bigint NOT NULL
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
-- Name: migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations (
    number integer NOT NULL
);


--
-- Name: streams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.streams (
    id bigint NOT NULL,
    context character varying NOT NULL,
    stream_name character varying NOT NULL,
    stream_id character varying NOT NULL,
    stream_revision integer DEFAULT '-1'::integer NOT NULL
);


--
-- Name: streams_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.streams_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: streams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.streams_id_seq OWNED BY public.streams.id;


--
-- Name: event_types id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_types ALTER COLUMN id SET DEFAULT nextval('public.event_types_id_seq'::regclass);


--
-- Name: events global_position; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN global_position SET DEFAULT nextval('public.events_global_position_seq'::regclass);


--
-- Name: streams id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streams ALTER COLUMN id SET DEFAULT nextval('public.streams_id_seq'::regclass);


--
-- Name: event_types event_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_types
    ADD CONSTRAINT event_types_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: streams streams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streams
    ADD CONSTRAINT streams_pkey PRIMARY KEY (id);


--
-- Name: idx_event_types_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_event_types_type ON public.event_types USING btree (type);


--
-- Name: idx_events_event_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_event_type_id ON public.events USING btree (event_type_id);


--
-- Name: idx_events_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_global_position ON public.events USING btree (global_position);


--
-- Name: idx_events_link_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_link_id ON public.events USING btree (link_id);


--
-- Name: idx_events_stream_id_and_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_stream_id_and_revision ON public.events USING btree (stream_id, stream_revision);


--
-- Name: idx_streams_context_and_stream_name_and_stream_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_streams_context_and_stream_name_and_stream_id ON public.streams USING btree (context, stream_name, stream_id);


--
-- Name: events events_event_type_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_event_type_fk FOREIGN KEY (event_type_id) REFERENCES public.event_types(id);


--
-- Name: events events_link_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_link_fk FOREIGN KEY (link_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: events events_stream_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_stream_fk FOREIGN KEY (stream_id) REFERENCES public.streams(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

