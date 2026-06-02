# frozen_string_literal: true

module PgEventstore
  module TestHelpers
    class << self
      def clean_up_db
        clean_up_data
        clean_up_partitions
        clean_up_views
      end

      def clean_up_partitions
        PgEventstore.connection.with do |conn|
          # Dropping parent partition also drops all child partitions
          conn.exec("select tablename from pg_tables where tablename like 'contexts_%'").each do |attrs|
            conn.exec("drop table #{attrs['tablename']}")
          end
        end
      end

      def clean_up_data
        tables_to_purge = PgEventstore.connection.with do |conn|
          conn.exec(<<~SQL)
            SELECT tablename
            FROM pg_catalog.pg_tables
            WHERE schemaname NOT IN ('pg_catalog', 'information_schema') AND tablename != 'migrations'
          SQL
        end
        tables_to_purge = tables_to_purge.map { |attrs| attrs['tablename'] }
        tables_to_purge.each do |table_name|
          PgEventstore.connection.with { |c| c.exec("DELETE FROM #{table_name}") }
        end
      end

      def clean_up_views
        views_to_purge = PgEventstore.connection.with do |conn|
          conn.exec(<<~SQL)
            SELECT table_name
            FROM information_schema.views
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema') AND table_name LIKE 'subscription_%'
          SQL
        end
        views_to_purge = views_to_purge.map { |attrs| attrs['table_name'] }
        views_to_purge.each do |view_name|
          PgEventstore.connection.with { |c| c.exec("DROP VIEW #{view_name}") }
        end
      end
    end
  end
end
