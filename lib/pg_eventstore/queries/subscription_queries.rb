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

      deserialize(pg_result.to_a.first)
    end

    # @param id [Integer]
    # @return [Hash]
    # @raise [PgEventstore::RecordNotFound]
    def find!(id)
      find_by(id: id) || raise(RecordNotFound.new("subscriptions", id))
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
      deserialize(pg_result.to_a.first)
    end

    # @param id [Integer]
    # @param attrs [Hash]
    def update(id, attrs)
      attrs = { updated_at: Time.now.utc }.merge(attrs)
      attrs_sql = attrs.keys.map.with_index(1) do |attr, index|
        "#{attr} = $#{index}"
      end.join(', ')
      sql =
        "UPDATE subscriptions SET #{attrs_sql} WHERE id = $#{attrs.keys.size + 1} RETURNING *"
      pg_result = connection.with do |conn|
        conn.exec_params(sql, [*attrs.values, id])
      end
      raise(RecordNotFound.new("subscriptions", id)) if pg_result.ntuples.zero?

      deserialize(pg_result.to_a.first)
    end

    # @param query_options [Array<Array<Integer, Hash>>] array of runner ids and query options
    # @return [Array<Hash>] array of raw events
    def subscriptions_events(query_options)
      return [] if query_options.empty?

      final_builder = union_builders(query_options.map { |id, opts| query_builder(id, opts) })
      connection.with do |conn|
        conn.exec_params(*final_builder.to_exec_params)
      end.to_a
    end

    # @param id [Integer] subscription's id
    # @param lock_id [String] UUIDv4 id of the subscriptions set which reserves the subscription
    # @param force [Boolean] whether to lock the subscription despite on #locked_by value
    # @return [String] UUIDv4 lock id
    # @raise [SubscriptionAlreadyLockedError] in case the Subscription is already locked
    def lock!(id, lock_id, force = false)
      transaction_queries.transaction do
        attrs = find!(id)
        if attrs[:locked_by] && !force
          raise SubscriptionAlreadyLockedError.new(attrs[:set], attrs[:name], attrs[:locked_by])
        end
        connection.with do |conn|
          conn.exec_params('UPDATE subscriptions SET locked_by = $1 WHERE id = $2', [lock_id, id])
        end
      end
      lock_id
    end

    # @param id [Integer] subscription's id
    # @param lock_id [String] UUIDv4 id of the set which reserved the subscription after itself
    # @return [void]
    # @raise [SubscriptionUnlockError] in case the Subscription is locked by some SubscriptionsSet, other than the one,
    #   persisted in memory
    def unlock!(id, lock_id)
      transaction_queries.transaction do
        attrs = find!(id)
        # Normally this should never happen as locking/unlocking happens within the same process. This is done only for
        # the matter of consistency.
        unless attrs[:locked_by] == lock_id
          raise SubscriptionUnlockError.new(attrs[:set], attrs[:name], lock_id, attrs[:locked_by])
        end
        connection.with do |conn|
          conn.exec_params('UPDATE subscriptions SET locked_by = $1 WHERE id = $2', [nil, id])
        end
      end
    end

    private

    # @param id [Integer] runner id
    # @param options [Hash] query options
    # @return [PgEventstore::SQLBuilder]
    def query_builder(id, options)
      builder = PgEventstore::QueryBuilders::EventsFiltering.subscriptions_events_filtering(
        event_type_queries.include_event_types_ids(options)
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

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end

    # @return [PgEventstore::EventTypeQueries]
    def event_type_queries
      EventTypeQueries.new(connection)
    end

    # @param hash [Hash]
    # @return [Hash]
    def deserialize(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
