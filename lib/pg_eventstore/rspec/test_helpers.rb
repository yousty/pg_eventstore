# frozen_string_literal: true

module PgEventstore
  module TestHelpers
    class << self
      def clean_up_db
        clean_up_data
        clean_up_partitions
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
        end.map { |attrs| attrs['tablename'] }
        tables_to_purge.each do |table_name|
          PgEventstore.connection.with { |c| c.exec("DELETE FROM #{table_name}") }
        end
      end
    end
  end
end
