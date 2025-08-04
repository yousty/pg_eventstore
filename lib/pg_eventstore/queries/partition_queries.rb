# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class PartitionQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param stream [PgEventstore::Stream]
    # @return [Hash] partition attributes
    def create_context_partition(stream)
      attributes = { context: stream.context, table_name: context_partition_name(stream) }

      loop do
        break unless partition_name_taken?(attributes[:table_name])

        attributes[:table_name] = attributes[:table_name].next
      end

      partition_sql = <<~SQL
        INSERT INTO partitions (#{attributes.keys.join(', ')})
          VALUES (#{Utils.positional_vars(attributes.values)}) RETURNING *
      SQL
      partition = connection.with do |conn|
        conn.exec_params(partition_sql, [*attributes.values])
      end.to_a.first
      connection.with do |conn|
        conn.exec(<<~SQL)
          CREATE TABLE #{attributes[:table_name]} PARTITION OF events
            FOR VALUES IN('#{conn.escape_string(stream.context)}') PARTITION BY LIST (stream_name)
        SQL
      end
      partition
    end

    # @param stream [PgEventstore::Stream]
    # @param context_partition_name [String]
    # @return [Hash] partition attributes
    def create_stream_name_partition(stream, context_partition_name)
      attributes = {
        context: stream.context, stream_name: stream.stream_name, table_name: stream_name_partition_name(stream)
      }

      loop do
        break unless partition_name_taken?(attributes[:table_name])

        attributes[:table_name] = attributes[:table_name].next
      end

      partition_sql = <<~SQL
        INSERT INTO partitions (#{attributes.keys.join(', ')})
          VALUES (#{Utils.positional_vars(attributes.values)}) RETURNING *
      SQL
      partition = connection.with do |conn|
        conn.exec_params(partition_sql, [*attributes.values])
      end.to_a.first
      connection.with do |conn|
        conn.exec(<<~SQL)
          CREATE TABLE #{attributes[:table_name]} PARTITION OF #{context_partition_name}
            FOR VALUES IN('#{conn.escape_string(stream.stream_name)}') PARTITION BY LIST (type)
        SQL
      end
      partition
    end

    # @param stream [PgEventstore::Stream]
    # @param event_type [String]
    # @param stream_name_partition_name [String]
    # @return [Hash] partition attributes
    def create_event_type_partition(stream, event_type, stream_name_partition_name)
      attributes = {
        context: stream.context, stream_name: stream.stream_name, event_type: event_type,
        table_name: event_type_partition_name(stream, event_type)
      }

      loop do
        break unless partition_name_taken?(attributes[:table_name])

        attributes[:table_name] = attributes[:table_name].next
      end

      partition_sql = <<~SQL
        INSERT INTO partitions (#{attributes.keys.join(', ')})
          VALUES (#{Utils.positional_vars(attributes.values)}) RETURNING *
      SQL
      partition = connection.with do |conn|
        conn.exec_params(partition_sql, [*attributes.values])
      end.to_a.first
      connection.with do |conn|
        conn.exec(<<~SQL)
          CREATE TABLE #{attributes[:table_name]} PARTITION OF #{stream_name_partition_name}
            FOR VALUES IN('#{conn.escape_string(event_type)}')
        SQL
      end
      partition
    end

    # @param stream [PgEventstore::Stream]
    # @param event_type [String]
    # @return [Boolean]
    def partition_required?(stream, event_type)
      event_type_partition(stream, event_type).nil?
    end

    # @param stream [PgEventstore::Stream]
    # @param event_type [String]
    # @return [void]
    def create_partitions(stream, event_type)
      return unless partition_required?(stream, event_type)

      context_partition = context_partition(stream) || create_context_partition(stream)
      stream_name_partition =
        stream_name_partition(stream) || create_stream_name_partition(stream, context_partition['table_name'])

      create_event_type_partition(stream, event_type, stream_name_partition['table_name'])
    end

    # @param stream [PgEventstore::Stream]
    # @return [Hash, nil] partition attributes
    def context_partition(stream)
      connection.with do |conn|
        conn.exec_params(
          'select * from partitions where context = $1 and stream_name is null and event_type is null',
          [stream.context]
        )
      end.first
    end

    # @param stream [PgEventstore::Stream]
    # @return [Hash, nil] partition attributes
    def stream_name_partition(stream)
      connection.with do |conn|
        conn.exec_params(
          <<~SQL,
            select * from partitions where context = $1 and stream_name = $2 and event_type is null
          SQL
          [stream.context, stream.stream_name]
        )
      end.first
    end

    # @param stream [PgEventstore::Stream]
    # @param event_type [String]
    # @return [Hash, nil] partition attributes
    def event_type_partition(stream, event_type)
      connection.with do |conn|
        conn.exec_params(
          <<~SQL,
            select * from partitions where context = $1 and stream_name = $2 and event_type = $3
          SQL
          [stream.context, stream.stream_name, event_type]
        )
      end.first
    end

    # @param table_name [String]
    # @return [Boolean]
    def partition_name_taken?(table_name)
      connection.with do |conn|
        conn.exec_params('select 1 as exists from partitions where table_name = $1', [table_name])
      end.to_a.dig(0, 'exists') == 1
    end

    # @param ids [Array<Integer>]
    # @return [Array<Hash>]
    def find_by_ids(ids)
      connection.with do |conn|
        conn.exec_params('select * from partitions where id = ANY($1::bigint[])', [ids])
      end.to_a
    end

    # @param stream_filters [Array<Hash[Symbol, String]>]
    # @param event_filters [Array<String>]
    # @return [Array<PgEventstore::Partition>]
    def partitions(stream_filters, event_filters)
      partitions_filter = QueryBuilders::PartitionsFiltering.new
      stream_filters.each { |attrs| partitions_filter.add_stream_attrs(**attrs) }
      partitions_filter.add_event_types(event_filters)
      partitions_filter.with_event_types
      connection.with do |conn|
        conn.exec_params(*partitions_filter.to_exec_params)
      end.map(&method(:deserialize))
    end

    # @param stream [PgEventstore::Stream]
    # @return [String]
    def context_partition_name(stream)
      "contexts_#{Digest::MD5.hexdigest(stream.context)[0..5]}"
    end

    # @param stream [PgEventstore::Stream]
    # @return [String]
    def stream_name_partition_name(stream)
      "stream_names_#{Digest::MD5.hexdigest("#{stream.context}-#{stream.stream_name}")[0..5]}"
    end

    # @param stream [PgEventstore::Stream]
    # @param event_type [String]
    # @return [String]
    def event_type_partition_name(stream, event_type)
      "event_types_#{Digest::MD5.hexdigest("#{stream.context}-#{stream.stream_name}-#{event_type}")[0..5]}"
    end

    private

    # @param attrs [Hash]
    # @return [PgEventstore::Partition]
    def deserialize(attrs)
      Partition.new(**attrs.transform_keys(&:to_sym))
    end
  end
end
