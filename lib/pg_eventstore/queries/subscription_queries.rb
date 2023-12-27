# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionQueries
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param attrs [Hash]
    # @return [Hash]
    def find_or_create_by(attrs)
      transaction_queries.transaction do
        find_by(attrs) || create(attrs)
      end
    end

    # @param attrs [Hash]
    # @return [Hash, nil]
    def find_by(attrs)
      builder = SQLBuilder.new.select('*').from('subscriptions')
      attrs.each do |attr, val|
        builder.where("#{attr} = ?", val)
      end

      pg_result = connection.with do |conn|
        conn.exec_params(*builder.to_exec_params)
      end
      return if pg_result.ntuples.zero?

      pg_result.to_a.first.transform_keys(&:to_sym)
    end

    # @param attrs [Hash]
    # @return [Hash]
    def create(attrs)
      sql = <<~SQL
        INSERT INTO subscriptions (#{attrs.keys.join(', ')}) 
          VALUES (#{Utils.positional_vars(attrs.values)}) 
          RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, attrs.values)
      end
      pg_result.to_a.first.transform_keys(&:to_sym)
    end

    # @param subscription [PgEventstore::Subscription]
    # @param attrs [Hash]
    def update(subscription, attrs)
      attrs = { updated_at: Time.now.utc }.merge(attrs)
      attrs_sql = attrs.keys.map.with_index(1) do |attr, index|
        "#{attr} = $#{index}"
      end.join(', ')
      sql =
        "UPDATE subscriptions SET #{attrs_sql} WHERE id = $#{attrs.keys.size + 1} RETURNING #{attrs.keys.join(', ')}"
      pg_result = connection.with do |conn|
        conn.exec_params(sql, [*attrs.values, subscription.id])
      end
      subscription.assign_attributes(pg_result.to_a.first)
    end

    # @param query_options [Array<Array<Integer, Hash>>] array of runner ids and query options
    # @return [Array<Hash>] array of raw events
    def subscriptions_events(query_options)
      final_builder = union_builders(query_options.map { |id, opts| query_builder(id, opts) })
      connection.with do |conn|
        conn.exec_params(*final_builder.to_exec_params)
      end.to_a
    end

    # @param id [Integer] subscription's id
    # @param lock_id [String] UUIDv4 id of the set which reserves the subscription after itself
    # @return [Hash]
    def lock!(id, lock_id)
      transaction_queries.transaction do
        attrs = find_by(id: id)
        raise(<<~TEXT) unless attrs[:locked_by].nil?
          Could not lock Subscription from #{attrs[:set].inspect} set with #{attrs[:name].inspect} name. It is \
          already locked by #{attrs[:locked_by].inspect} set.
        TEXT
        connection.with do |conn|
          conn.exec_params('UPDATE subscriptions SET locked_by = $1 WHERE id = $2', [lock_id, id])
        end
      end
      { locked_by: lock_id }
    end

    # @param id [Integer] subscription's id
    # @param lock_id [String] UUIDv4 id of the set which reserved the subscription after itself
    # @return [Hash]
    def unlock!(id, lock_id)
      transaction_queries.transaction do
        attrs = find_by(id: id)
        # Normally this should never happen as locking/unlocking happens within the same process. This is done only for
        # the matter of consistency.
        raise(<<~TEXT) unless attrs[:locked_by] == lock_id
          Failed to unlock Subscription##{id} by #{lock_id.inspect} lock id - it is locked by \
          #{attrs[:locked_by].inspect} lock id.
        TEXT

        connection.with do |conn|
          conn.exec_params('UPDATE subscriptions SET locked_by = $1 WHERE id = $2', [nil, id])
        end
      end
      { locked_by: nil }
    end

    private

    # @param id [Integer] runner id
    # @param options [Integer] query options
    # @return [PgEventstore::SQLBuilder]
    def query_builder(id, options)
      builder = PgEventstore::QueryBuilders::EventsFiltering.all_stream_filtering(
        options.slice(:from_position, :resolve_link_tos, :filter, :max_count)
      ).to_sql_builder
      builder.select("#{id} as runner_id")
    end

    # @param builders [Array<PgEventstore::SQLBuilder>]
    # @return [PgEventstore::SQLBuilder]
    def union_builders(builders)
      builders[1..].each_with_object(builders[0]) do |builder, first_builder|
        first_builder.union(builder)
      end
    end

    def transaction_queries
      TransactionQueries.new(connection)
    end
  end
end
