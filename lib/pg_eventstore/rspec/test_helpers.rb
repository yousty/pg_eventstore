# frozen_string_literal: true

module PgEventstore
  module TestHelpers
    class << self
      def clean_up_db(config = :default)
        clean_up_data(config)
        clean_up_partitions(config)
        clean_up_subscription_functions(config)
      end

      def clean_up_partitions(config)
        PgEventstore.connection(config).with do |conn|
          # Dropping parent partition also drops all child partitions
          conn.exec("select tablename from pg_tables where tablename like 'contexts_%'").each do |attrs|
            conn.exec("drop table #{attrs['tablename']}")
          end
        end
      end

      def clean_up_data(config)
        tables_to_purge = PgEventstore.connection(config).with do |conn|
          conn.exec(<<~SQL)
            SELECT tablename
            FROM pg_catalog.pg_tables
            WHERE schemaname NOT IN ('pg_catalog', 'information_schema') AND tablename != 'migrations'
          SQL
        end
        tables_to_purge = tables_to_purge.map { |attrs| attrs['tablename'] }
        tables_to_purge.each do |table_name|
          PgEventstore.connection(config).with { |c| c.exec("DELETE FROM #{table_name}") }
        end
      end

      def clean_up_subscription_functions(config)
        functions_to_purge = PgEventstore.connection(config).with do |conn|
          conn.exec(<<~SQL)
            SELECT proname FROM pg_proc WHERE proname LIKE 'subscription_%'
          SQL
        end
        functions_to_purge = functions_to_purge.map { _1['proname'] }
        functions_to_purge.each do |function_name|
          PgEventstore.connection(config).with { |c| c.exec("drop function #{function_name}") }
        end
      end
    end
  end
end
