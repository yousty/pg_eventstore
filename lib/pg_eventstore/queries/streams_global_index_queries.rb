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
        find_by(stream) || create(stream)
      end
    end

    def find_by(stream)
      idx_partitions_filter = QueryBuilders::Filters::Collection.from_options({ filter: { streams: [stream.to_hash] } })
      filtering = QueryBuilders::StreamsGlobalIndexFiltering.new
      idx_partitions_filter.collection.each(&filtering.method(:add_filter_row))
      deserialize_one(@query_strategy.exec_params(*filtering.to_exec_params))
    end

    def find_by!(stream)
      find_by(stream) ||
        raise(RecordNotFound.new(QueryBuilders::StreamsGlobalIndexFiltering::PRIMARY_TABLE_NAME, stream))
    end

    def update_revision(id, stream_revision:)
      @query_strategy.exec_params(<<~SQL, [id, stream_revision])
        UPDATE streams_global_index SET stream_revision = $2 WHERE id = $1
      SQL
    end

    def update(id, **attrs)
      attrs_sql = attrs.keys.map.with_index(2) do |attr, index|
        "#{attr} = $#{index}"
      end.join(', ')
      @query_strategy.exec_params(<<~SQL, [id, *attrs.values])
        UPDATE streams_global_index SET #{attrs_sql} WHERE id = $1
      SQL
    end

    def create(stream)
      filter_collection = QueryBuilders::Filters::Collection.from_options(
        { filter: { streams: [{ context: stream.context, stream_name: stream.stream_name }] } }
      )
      partitions_sql_builder = QueryBuilders::PartitionsFiltering.assemble_sql_builder(
        filter_collection,
        scope: :stream_name
      )
      partitions_sql_builder.unselect.select('id')
      sql, positional_args = partitions_sql_builder.to_exec_params
      stream_revision = Stream::NON_EXISTING_STREAM_REVISION
      starting_position = StreamGlobalIndex::INITIAL_STARTING_POSITION
      stream_id = PG::Connection.escape(stream.stream_id)
      value = "((#{sql}), '#{stream_id}', #{stream_revision}, #{starting_position})"

      res = @query_strategy.exec_params(<<~SQL, positional_args)
        INSERT INTO streams_global_index ("partition_id", "stream_id", "stream_revision", "starting_position")
        VALUES #{value} RETURNING *
      SQL
      deserialize_one(res)
    end

    def delete(id)
      res = @query_strategy.exec_params('delete from streams_global_index where id = $1', [id])
      res.cmd_tuples == 1
    end

    def stream_exists?(stream)
      idx_partitions_filter = QueryBuilders::Filters::Collection.from_options({ filter: { streams: [stream.to_hash] } })
      filtering = QueryBuilders::StreamsGlobalIndexFiltering.new
      idx_partitions_filter.collection.each(&filtering.method(:add_filter_row))
      builder = filtering.to_sql_builder.unselect.select('1 as exists')
      @query_strategy.exec_params(*builder.to_exec_params).ntuples == 1
    end

    def stream_revision(stream)
      idx_partitions_filter = QueryBuilders::Filters::Collection.from_options({ filter: { streams: [stream.to_hash] } })
      filtering = QueryBuilders::StreamsGlobalIndexFiltering.new
      idx_partitions_filter.collection.each(&filtering.method(:add_filter_row))
      builder = filtering.to_sql_builder.unselect.select('stream_revision')
      @query_strategy.exec_params(*builder.to_exec_params).first&.dig('stream_revision')
    end

    private

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end

    def deserialize_one(pg_result)
      first_result = pg_result.first
      return unless first_result

      StreamGlobalIndex.new(first_result)
    end
  end
end
