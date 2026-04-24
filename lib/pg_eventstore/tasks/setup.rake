# frozen_string_literal: true

require 'uri'

module PgEventstore
  class MigrationHelpers
    class << self
      def postgres_uri
        @postgres_uri ||=
          begin
            uri = URI.parse(ENV.fetch('PG_EVENTSTORE_URI'))
            uri.path = '/postgres'
            uri.to_s
          end
      end

      def db_name
        @db_name ||= URI.parse(ENV.fetch('PG_EVENTSTORE_URI')).path&.delete('/')
      end

      # This method is idempotent
      def setup_pg_cron
        PgEventstore.connection(:_postgres_db_connection).with do |conn|
          conn.exec(<<~SQL)
            CREATE EXTENSION IF NOT EXISTS pg_cron
          SQL
          conn.exec_params(<<~SQL, ["prune_#{db_name}_events_horizon", db_name])
            SELECT cron.schedule_in_database(
              $1,
              '*/10 * * * *',
              $$DELETE FROM events_horizon WHERE xact_id <= (SELECT xact_id FROM events_horizon ORDER BY xact_id DESC OFFSET 100 LIMIT 1)$$,
              $2
            )
          SQL
          # Store information about finished cron jobs for 1 day
          conn.exec(<<~SQL)
            SELECT cron.schedule(
              'delete-job-run-details',
              '0 12 * * *',
              $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '1 day'$$
            );
          SQL
        end
      end
    end
  end
end

PgEventstore.configure(name: :_postgres_db_connection) do |config|
  config.pg_uri = PgEventstore::MigrationHelpers.postgres_uri
end

PgEventstore.configure(name: :_eventstore_db_connection) do |config|
  config.pg_uri = ENV['PG_EVENTSTORE_URI']
end

namespace :pg_eventstore do
  desc 'Creates events table, indexes, etc.'
  task :create do
    PgEventstore.connection(:_postgres_db_connection).with do |conn|
      exists =
        conn.exec_params('SELECT 1 as exists FROM pg_database where datname = $1', [PgEventstore::MigrationHelpers.db_name]).
        first&.dig('exists')
      if exists
        puts "#{PgEventstore::MigrationHelpers.db_name} already exists. Skipping."
      else
        escaped_db_name = conn.escape_string(PgEventstore::MigrationHelpers.db_name)
        conn.exec("CREATE DATABASE #{escaped_db_name} WITH OWNER #{conn.escape_string(conn.user)}")
        PgEventstore::MigrationHelpers.setup_pg_cron
      end
    end
  end

  task :migrate do
    migration_files_root = "#{Gem::Specification.find_by_name('pg_eventstore').gem_dir}/db/migrations"

    PgEventstore.connection(:_eventstore_db_connection).with do |conn|
      conn.exec('CREATE TABLE IF NOT EXISTS migrations (number int NOT NULL)')
      latest_migration =
        conn.exec('SELECT number FROM migrations ORDER BY number DESC LIMIT 1').to_a.dig(0, 'number') || -1

      Dir.chdir migration_files_root do
        Dir['*.{sql,rb}'].sort_by { |f_name| f_name.split('_').first.to_i }.each do |f_name|
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

  desc 'Drops events table and related pg_eventstore objects.'
  task :drop do
    PgEventstore.connection(:_postgres_db_connection).with do |conn|
      conn.exec("DROP DATABASE IF EXISTS #{conn.escape_string(PgEventstore::MigrationHelpers.db_name)}")
    end
  end
end
