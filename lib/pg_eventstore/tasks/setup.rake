# frozen_string_literal: true

namespace :pg_eventstore do
  desc "Creates events table, indexes, etc."
  task :create do
    PgEventstore.configure do |config|
      config.pg_uri = ENV['PG_EVENTSTORE_URI']
    end

    db_files_root = "#{Gem::Specification.find_by_name("pg_eventstore").gem_dir}/db/initial"

    PgEventstore.connection.with do |conn|
      conn.transaction do
        conn.exec(File.read("#{db_files_root}/extensions.sql"))
        conn.exec(File.read("#{db_files_root}/tables.sql"))
        conn.exec(File.read("#{db_files_root}/primary_and_foreign_keys.sql"))
        conn.exec(File.read("#{db_files_root}/indexes.sql"))
      end
    end
  end

  task :migrate do
    PgEventstore.configure do |config|
      config.pg_uri = ENV['PG_EVENTSTORE_URI']
    end

    migration_files_root = "#{Gem::Specification.find_by_name("pg_eventstore").gem_dir}/db/migrations"

    PgEventstore.connection.with do |conn|
      conn.exec('CREATE TABLE IF NOT EXISTS migrations (number int NOT NULL)')
      latest_migration =
        conn.exec('SELECT number FROM migrations ORDER BY number DESC LIMIT 1').to_a.dig(0, 'number') || -1

      Dir.chdir migration_files_root do
        Dir["*.{sql,rb}"].sort_by { |f_name| f_name.split('_').first.to_i }.each do |f_name|
          number = File.basename(f_name).split('_')[0].to_i
          next if latest_migration >= number

          if File.extname(f_name) == '.rb'
            load f_name
          else
            conn.exec(File.read(f_name))
          end
          conn.exec_params('INSERT INTO migrations (number) VALUES ($1)', [number])
        end
      end
    end
  end

  desc "Drops events table and related pg_eventstore objects."
  task :drop do
    PgEventstore.configure do |config|
      config.pg_uri = ENV['PG_EVENTSTORE_URI']
    end

    PgEventstore.connection.with do |conn|
      conn.exec <<~SQL
        DROP TABLE IF EXISTS public.events;
        DROP TABLE IF EXISTS public.streams;
        DROP TABLE IF EXISTS public.event_types;
        DROP TABLE IF EXISTS public.migrations;
        DROP EXTENSION IF EXISTS "uuid-ossp";
        DROP EXTENSION IF EXISTS pgcrypto;
      SQL
    end
  end
end
