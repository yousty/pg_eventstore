# frozen_string_literal: true

namespace :pg_eventstore do
  desc "Creates messages table, indexes."
  task :create_table do
    PgEventstore.configure do |config|
      config.pg_uri = ENV['PG_EVENTSTORE_URI']
    end

    PgEventstore.connection.with do |conn|
      conn.transaction do
        conn.exec <<~SQL
          CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
          CREATE EXTENSION IF NOT EXISTS pgcrypto;
        SQL
        conn.exec <<~SQL
          CREATE TABLE public.events (
            id uuid NOT NULL DEFAULT public.gen_random_uuid(),
            type character varying,
            global_position bigserial NOT NULL,
            context character varying NOT NULL,
            stream_name character varying NOT NULL,
            stream_id character varying NOT NULL,
            stream_revision bigint NOT NULL,
            data jsonb,
            metadata jsonb,
            link_id bigint,
            created_at timestamp without time zone NOT NULL DEFAULT now()
          );
        SQL
        conn.exec <<~SQL
          ALTER TABLE ONLY public.events ADD CONSTRAINT events_pkey PRIMARY KEY (global_position);
          ALTER TABLE ONLY public.events ADD CONSTRAINT events_link_fk FOREIGN KEY (link_id) 
            REFERENCES public.events(global_position) ON DELETE CASCADE;
        SQL
        conn.exec <<~SQL
          CREATE INDEX idx_events_type ON public.events USING btree (type); 
          CREATE INDEX idx_events_ctx_and_stream_name_and_stream_id ON public.events USING btree (context, stream_name, stream_id); 
          CREATE INDEX idx_events_link_id ON public.events USING btree (link_id);          
        SQL
      end
    end
  end

  desc "Drops messages table."
  task :drop_table do
    PgEventstore.configure do |config|
      config.pg_uri = ENV['PG_EVENTSTORE_URI']
    end

    PgEventstore.connection.with do |conn|
      conn.exec <<~SQL
        DROP TABLE IF EXISTS public.events;
      SQL
    end
  end
end
