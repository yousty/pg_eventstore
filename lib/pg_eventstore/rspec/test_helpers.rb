# frozen_string_literal: true

module PgEventstore
  module TestHelpers
    class << self
      def clean_up_db
        tables_to_purge = PgEventstore.connection.with do |conn|
          conn.exec(<<~SQL)
            SELECT tablename 
            FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema') AND tablename != 'migrations'                
          SQL
        end.map { |attrs| attrs['tablename'] }
        tables_to_purge.each do |table_name|
          PgEventstore.connection.with { |c| c.exec("DELETE FROM #{table_name}") }
        end
      end
    end
  end
end
