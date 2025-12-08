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
    # @param scope [Symbol] what kind of partition we want to receive. Available options are :event_type, :context,
    #   :stream_name and :auto. In :auto mode the scope will be calculated based on stream_filters and event_filters.
    # @return [Array<PgEventstore::Partition>]
    def partitions(stream_filters, event_filters, scope: :event_type)
      stream_filters = stream_filters.select { QueryBuilders::PartitionsFiltering.correct_stream_filter?(_1) }
      sql_builder =
        if event_filters.any?
          # When event type filters are present - they apply constraints to any stream filter. Thus, we can't look up
          # partitions by stream attributes separately.
          filter = QueryBuilders::PartitionsFiltering.new
          stream_filters.each { |attrs| filter.add_stream_attrs(**attrs) }
          filter.add_event_types(event_filters)
          set_partitions_scope(filter, stream_filters, event_filters, scope)
        else
          # When event type filters are absent - we can look up partitions by context and context/stream_name
          # separately, thus potentially producing one-to-one mapping of filter-to-partition with :auto scope. For
          # example, let's say we have stream attributes filter like
          # [{ context: 'FooCtx', stream_name: 'Bar'}, { context: 'BarCtx' }], then we would be able to look up
          # partitions by the exact match, returning only two of them according to the provided filters - stream
          # partition for first filter and context partition for second filter.
          builders = stream_filters.map do |attrs|
            filter = QueryBuilders::PartitionsFiltering.new
            filter.add_stream_attrs(**attrs)
            set_partitions_scope(filter, [attrs], event_filters, scope)
          end

          sql_builder = SQLBuilder.union_builders(builders) if builders.any?
          sql_builder ||
            begin
              builder = QueryBuilders::PartitionsFiltering.new
              set_partitions_scope(builder, stream_filters, event_filters, scope)
            end
        end

      connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
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

    # @param partitions_filter [PgEventstore::QueryBuilders::PartitionsFiltering]
    # @param stream_filters [Array<Hash[Symbol, String]>]
    # @param event_filters [Array<String>]
    # @param scope [Symbol]
    # @return [PgEventstore::SQLBuilder]
    def set_partitions_scope(partitions_filter, stream_filters, event_filters, scope)
      case scope
      when :event_type
        partitions_filter.with_event_types
      when :stream_name
        filter = QueryBuilders::PartitionsFiltering.new
        filter.without_event_types
        filter.with_stream_names
        builder = filter.to_sql_builder
        builder.where(
          '(context, stream_name) in ?',
          partitions_filter.to_sql_builder.unselect.select('context, stream_name').group('context, stream_name')
        )
      when :context
        filter = QueryBuilders::PartitionsFiltering.new
        filter.without_event_types
        filter.without_stream_names
        builder = filter.to_sql_builder
        builder.where('context in ?', partitions_filter.to_sql_builder.unselect.select('context').group('context'))
      when :auto
        if event_filters.any?
          set_partitions_scope(partitions_filter, stream_filters, event_filters, :event_type)
        elsif stream_filters.any? { _1[:stream_name] }
          set_partitions_scope(partitions_filter, stream_filters, event_filters, :stream_name)
        else
          set_partitions_scope(partitions_filter, stream_filters, event_filters, :context)
        end
      else
        raise NotImplementedError, "Don't know how to handle #{scope.inspect} scope!"
      end
    end

    # @param attrs [Hash]
    # @return [PgEventstore::Partition]
    def deserialize(attrs)
      Partition.new(**attrs.transform_keys(&:to_sym))
    end
  end
end
