# frozen_string_literal: true

module PartitionsHelper
  def partition_table(table_name)
    PgEventstore.connection.with do |conn|
      conn.exec_params('select * from pg_tables where tablename = $1', [table_name])
    end.first
  end
end
