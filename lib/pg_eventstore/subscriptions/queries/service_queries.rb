# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class ServiceQueries
    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param relation_oids [Array<Integer>]
    # @return [Array<String>]
    def relation_transaction_ids(relation_oids)
      result = @connection.with do |conn|
        # Look up transactions that change table's content
        conn.exec_params(
          <<~SQL,
            SELECT virtualtransaction AS trx_id FROM pg_locks
              WHERE relation = ANY($1::oid[]) AND mode = 'RowExclusiveLock'
          SQL
          [relation_oids]
        )
      end
      result.map { _1['trx_id'] }
    end

    # @param relation_ids [Array<Integer>]
    # @param transaction_ids [Array<String>]
    # @return [Boolean]
    def transactions_in_progress?(relation_ids:, transaction_ids:)
      result = @connection.with do |conn|
        conn.exec_params(
          <<~SQL,
            SELECT 1 as one FROM pg_locks
              WHERE virtualtransaction = ANY($1) AND relation = ANY($2::oid[]) AND mode = 'RowExclusiveLock'
              LIMIT 1
          SQL
          [transaction_ids, relation_ids]
        )
      end
      result.any?
    end

    # @param table_names [Array<String>] existing table names
    # @return [Integer]
    def max_global_position(table_names)
      return 0 if table_names.empty?

      partition_builds = table_names.map do |table_name|
        SQLBuilder.new.select("MAX(#{table_name}.global_position) AS global_position").from(table_name)
      end
      sql, positional_values = SQLBuilder.union_builders(partition_builds).to_exec_params
      result = @connection.with do |conn|
        conn.exec_params("SELECT MAX(global_position) AS max_pos FROM (#{sql}) pos", positional_values)
      end
      result.first['max_pos'] || 0
    end

    # @param table_names [Array<String>]
    # @return [Hash<String, Integer>]
    def relation_ids_by_names(table_names)
      result = @connection.with do |conn|
        conn.exec_params(
          <<~SQL,
            SELECT relname, oid FROM pg_class WHERE relname = ANY($1::varchar[])
          SQL
          [table_names]
        )
      end
      result.each_with_object({}) { |attrs, res| res[attrs['relname']] = attrs['oid'] }
    end
  end
end
