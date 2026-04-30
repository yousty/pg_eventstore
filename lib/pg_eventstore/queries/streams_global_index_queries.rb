# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class StreamsGlobalIndexQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    # @param query_strategy [PgEventstore::QueryStrategy]
    def initialize(connection, query_strategy)
      @connection = connection
      @query_strategy = query_strategy
    end

    def find_or_create_by(stream)
      transaction_queries.transaction do
        find_by(stream) || create(stream, stream_revision: Stream::NON_EXISTING_STREAM_REVISION)
      end
    end

    def find_by(stream)
      idx_partitions_filter = QueryBuilders::IndexPartitionsFilter.create_from_stream(stream)
      filter = QueryBuilders::StreamsGlobalIndexFiltering.new
      filter.add_partition_filters(idx_partitions_filter)
      @query_strategy.exec_params(*filter.to_exec_params).to_a.first
    end

    def update_revision(id, stream_revision:)
      @query_strategy.exec_params(<<~SQL, [id, stream_revision])
        UPDATE streams_global_index SET stream_revision = $2 WHERE id = $1
      SQL
    end

    def create(stream, stream_revision:)
      partitions_sql_builder = QueryBuilders::PartitionsFiltering.assemble_sql_builder(
        [{ context: stream.context, stream_name: stream.stream_name }],
        [],
        scope: :stream_name
      )
      partitions_sql_builder.unselect.select('id')
      sql, positional_args = partitions_sql_builder.to_exec_params
      value = "((#{sql}), '#{PG::Connection.escape(stream.stream_id)}', #{stream_revision})"

      @query_strategy.exec_params(<<~SQL, positional_args).to_a.first
        INSERT INTO streams_global_index ("partition_id", "stream_id", "stream_revision") VALUES #{value} RETURNING *
      SQL
    rescue PG::UniqueViolation => e
      raise DuplicatedRecordError.new(e)
    end

    def delete(stream)
      idx_partitions_filter = QueryBuilders::IndexPartitionsFilter.create_from_stream(stream)
      filter = QueryBuilders::StreamsGlobalIndexFiltering.new
      filter.add_partition_filters(idx_partitions_filter)
      builder = filter.to_sql_builder
      builder.unselect.select('id')
      sql, positional_args = builder.to_exec_params
      res = @query_strategy.exec_params("delete from streams_global_index where id = (#{sql})", positional_args)
      res.cmd_tuples == 1
    end

    def stream_exists?(stream)
      idx_partitions_filter = QueryBuilders::IndexPartitionsFilter.create_from_stream(stream)
      filter = QueryBuilders::StreamsGlobalIndexFiltering.new
      filter.add_partition_filters(idx_partitions_filter)
      builder = filter.to_sql_builder
      builder.unselect.select('1 as exists')
      @query_strategy.exec_params(*builder.to_exec_params).ntuples == 1
    end

    private

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end
  end
end
