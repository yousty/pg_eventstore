# frozen_string_literal: true

require 'uri'

helpers = Class.new do
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
      @db_name ||= URI.parse(ENV.fetch('PG_EVENTSTORE_URI')).path&.delete("/")
    end
  end
end

namespace :pg_eventstore do
  desc "Creates events table, indexes, etc."
  task :create do
    PgEventstore.configure do |config|
      config.pg_uri = helpers.postgres_uri
    end

    PgEventstore.connection.with do |conn|
      exists =
        conn.exec_params("SELECT 1 as exists FROM pg_database where datname = $1", [helpers.db_name]).first&.dig('exists')
      if exists
        puts "#{helpers.db_name} already exists. Skipping."
      else
        conn.exec("CREATE DATABASE #{conn.escape_string(helpers.db_name)} WITH OWNER #{conn.escape_string(conn.user)}")
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
      config.pg_uri = helpers.postgres_uri
    end

    PgEventstore.connection.with do |conn|
      conn.exec("DROP DATABASE IF EXISTS #{conn.escape_string(helpers.db_name)}")
    end
  end
end
