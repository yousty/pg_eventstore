# frozen_string_literal: true

module MaintenanceHelpers
  EMPTY_INDEX_SIZE = 8 * 1_024 # Empty index size is 8 KB

  def wait_for_reindex(index_name)
    loop do
      res = PgEventstore.connection.with do |conn|
        conn.exec_params(<<~SQL, [index_name]).first
          select 1 as one
          from pg_stat_progress_create_index s
              join pg_class on pg_class.oid = s.relid
          where pg_class.relname = $1
        SQL
      end
      break if res.nil?
    end
  end
end
