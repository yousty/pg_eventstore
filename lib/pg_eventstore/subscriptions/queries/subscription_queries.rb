# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
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
      builder = find_by_attrs_builder(attrs).limit(1)
      pg_result = connection.with do |conn|
        conn.exec_params(*builder.to_exec_params)
      end
      return if pg_result.ntuples == 0

      deserialize(pg_result.to_a.first)
    end

    # @param attrs [Hash]
    # @return [Array<Hash>]
    def find_all(attrs)
      builder = find_by_attrs_builder(attrs)
      pg_result = connection.with do |conn|
        conn.exec_params(*builder.to_exec_params)
      end
      return [] if pg_result.ntuples == 0

      pg_result.map(&method(:deserialize))
    end

    # @param state [String, nil]
    # @return [Array<String>]
    def set_collection(state = nil)
      builder = SQLBuilder.new.from('subscriptions').select('set').group('set').order('set ASC')
      builder.where('state = ?', state) if state
      raw_subscriptions = connection.with do |conn|
        conn.exec_params(*builder.to_exec_params)
      end
      raw_subscriptions.map { |attrs| attrs['set'] }
    end

    # @param id [Integer]
    # @return [Hash]
    # @raise [PgEventstore::RecordNotFound]
    def find!(id)
      find_by(id: id) || raise(RecordNotFound.new('subscriptions', id))
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
    # @param locked_by [Integer, nil]
    # @return [Hash]
    # @raise [PgEventstore::RecordNotFound]
    # @raise [PgEventstore::WrongLockIdError]
    def update(id, attrs:, locked_by:)
      attrs = { updated_at: Time.now.utc }.merge(attrs)
      attrs_sql = attrs.keys.map.with_index(1) do |attr, index|
        "#{attr} = $#{index}"
      end.join(', ')
      sql =
        "UPDATE subscriptions SET #{attrs_sql} WHERE id = $#{attrs.keys.size + 1} RETURNING *"
      updated_attrs = transaction_queries.transaction(:read_committed) do
        pg_result = connection.with do |conn|
          conn.exec_params(sql, [*attrs.values, id])
        end
        raise(RecordNotFound.new('subscriptions', id)) if pg_result.ntuples == 0

        updated_attrs = pg_result.to_a.first
        unless updated_attrs['locked_by'] == locked_by
          # Subscription is force-locked by someone else. We have to roll back such transaction
          raise(WrongLockIdError.new(updated_attrs['set'], updated_attrs['name'], updated_attrs['locked_by']))
        end

        updated_attrs
      end

      deserialize(updated_attrs)
    end

    # @param subscriptions_set_id [Integer] SubscriptionsSet#id
    # @param subscriptions_ids [Array<Integer>] Array of Subscription#id
    # @return [Hash<Integer => Time>]
    def ping_all(subscriptions_set_id, subscriptions_ids)
      pg_result = connection.with do |conn|
        sql = <<~SQL
          UPDATE subscriptions SET updated_at = $1 WHERE locked_by = $2 AND id = ANY($3::int[])
            RETURNING id, updated_at
        SQL
        conn.exec_params(sql, [Time.now.utc, subscriptions_set_id, subscriptions_ids])
      end
      pg_result.to_h do |attrs|
        [attrs['id'], attrs['updated_at']]
      end
    end

    # @param query_options [Hash{Integer => Hash}] runner_id/query options association
    # @return [Hash{Integer => Array<Hash>}] runner_id/events association
    def subscriptions_events(query_options)
      return {} if query_options.empty?

      final_builder = SQLBuilder.union_builders(query_options.map { |id, opts| query_builder(id, opts) })
      raw_events = connection.with do |conn|
        conn.exec_params(*final_builder.to_exec_params)
      end.to_a
      raw_events.group_by { _1['runner_id'] }.to_h do |runner_id, runner_raw_events|
        next [runner_id, runner_raw_events] unless query_options[runner_id][:resolve_link_tos]

        [runner_id, links_resolver.resolve(runner_raw_events)]
      end
    end

    # @param id [Integer] subscription's id
    # @param lock_id [Integer] id of the subscriptions set which reserves the subscription
    # @param force [Boolean] whether to lock the subscription despite on #locked_by value
    # @return [Integer] lock id
    # @raise [SubscriptionAlreadyLockedError] in case the Subscription is already locked
    def lock!(id, lock_id, force: false)
      transaction_queries.transaction do
        attrs = find!(id)
        # We don't care who locked the Subscription - whether it is the same SubscriptionsSet or not - multiple locks
        # must not happen even with the same SubscriptionsSet. We later assume this to reset Subscription's stats, for
        # example.
        if attrs[:locked_by] && !force
          raise SubscriptionAlreadyLockedError.new(attrs[:set], attrs[:name], attrs[:locked_by])
        end

        connection.with do |conn|
          conn.exec_params('UPDATE subscriptions SET locked_by = $1 WHERE id = $2', [lock_id, id])
        end
      end
      lock_id
    end

    # @param id [Integer]
    # @return [void]
    def delete(id)
      connection.with do |conn|
        conn.exec_params('DELETE FROM subscriptions WHERE id = $1', [id])
      end
    end

    private

    # @param id [Integer] runner id
    # @param options [Hash] query options
    # @return [PgEventstore::SQLBuilder]
    def query_builder(id, options)
      builder = PgEventstore::QueryBuilders::EventsFiltering.subscriptions_events_filtering(options).to_sql_builder
      builder.where('global_position <= ?', options[:to_position]) if options[:to_position]
      builder.select("#{id} as runner_id")
    end

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end

    # @return [PgEventstore::LinksResolver]
    def links_resolver
      LinksResolver.new(connection)
    end

    # @param hash [Hash]
    # @return [Hash]
    def deserialize(hash)
      hash.transform_keys(&:to_sym)
    end

    # @param attrs [Hash]
    # @return [PgEventstore::SQLBuilder]
    def find_by_attrs_builder(attrs)
      builder = SQLBuilder.new.select('*').from('subscriptions').order('id ASC')
      attrs.each do |attr, val|
        builder.where("#{attr} = ?", val)
      end
      builder
    end
  end
end
