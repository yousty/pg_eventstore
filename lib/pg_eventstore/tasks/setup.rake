# frozen_string_literal: true

namespace :pg_eventstore do
  desc "Creates messages table, indexes."
  task :create_table do
    PgEventstore.configure do |config|
      config.pg_uri = ENV['PG_EVENTSTORE_URI']
    end

    db_files_root = "#{Gem::Specification.find_by_name("pg_eventstore").gem_dir}/db"

    PgEventstore.connection.with do |conn|
      conn.transaction do
        conn.exec(File.read("#{db_files_root}/extensions.sql"))
        conn.exec(File.read("#{db_files_root}/tables.sql"))
        conn.exec(File.read("#{db_files_root}/primary_and_foreign_keys.sql"))
        conn.exec(File.read("#{db_files_root}/indexes.sql"))
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
        DROP EXTENSION IF EXISTS "uuid-ossp";
        DROP EXTENSION IF EXISTS pgcrypto;
      SQL
    end
  end
end
