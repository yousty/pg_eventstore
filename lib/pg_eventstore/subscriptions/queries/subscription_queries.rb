# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionQueries
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
      pg_result = @query_strategy.exec_params(*builder.to_exec_params)
      return if pg_result.ntuples == 0

      deserialize(pg_result.to_a.first)
    end

    # @param attrs [Hash]
    # @return [Array<Hash>]
    def find_all(attrs)
      builder = find_by_attrs_builder(attrs)
      pg_result = @query_strategy.exec_params(*builder.to_exec_params)
      return [] if pg_result.ntuples == 0

      pg_result.map(&method(:deserialize))
    end

    # @param state [String, nil]
    # @return [Array<String>]
    def set_collection(state = nil)
      builder = SQLBuilder.new.from('subscriptions').select('set').group('set').order('set ASC')
      builder.where('state = ?', state) if state
      raw_subscriptions = @query_strategy.exec_params(*builder.to_exec_params)
      raw_subscriptions.map { |attrs| attrs['set'] }
    end

    # @param id [Integer]
    # @return [Hash]
    # @raise [PgEventstore::RecordNotFound]
    def find!(id)
      find_by(id:) || raise(RecordNotFound.new('subscriptions', id))
    end

    # @param attrs [Hash]
    # @return [Hash]
    def create(attrs)
      sql = <<~SQL
        INSERT INTO subscriptions (#{attrs.keys.join(', ')})
          VALUES (#{Utils.positional_vars(attrs.values)})
          RETURNING *
      SQL
      pg_result = @query_strategy.exec_params(sql, attrs.values)
      deserialize(pg_result.to_a.first)
    end

    # @param id [Integer] Subscription#id
    # @param options [Hash]
    # @option options [Hash] :filter
    # @param locked_by [Integer] SubscriptionSet#id
    # @return [void]
    def create_or_replace_table_function(id, options, locked_by)
      filter_collection = QueryBuilders::Filters::Collection.from_options(options)
      builder = QueryBuilders::IndexBasedEventsFiltering.sql_builder_for_subscriptions(filter_collection.collection)
      function_name = QueryBuilders::SubscriptionEventsFiltering.new(id).to_table_name
      transaction_queries.transaction(:read_committed) do
        connection.with do |conn|
          attrs = conn.exec_params('select * from subscriptions where id = $1 for update', [id]).to_a.first
          unless attrs['locked_by'] == locked_by
            # Subscription is force-locked by someone else. We have to roll back such transaction
            raise(WrongLockIdError.new(attrs['set'], attrs['name'], attrs['locked_by']))
          end

          compiled = conn.compile(*builder.to_exec_params)
          compiled = <<~SQL
            create or replace function #{function_name}(
              from_position bigint,
              to_position bigint,
              max_count int
            )
            returns table (
              global_position bigint,
              event_type_partition_id bigint,
              subscription_position bigint
            )
            language plpgsql
            stable
            parallel safe
            as $$
            declare
              from_gpos bigint;
              to_gpos bigint;
            begin
              with candidates as (
                select esp.global_position
                from event_subscription_positions esp
                where esp.subscription_position >= from_position
                  and esp.subscription_position <= to_position
              )
              /* + 0 here is to keep PostgreSQL from trying to optimize the query by picking wrong index */
              select coalesce(min(candidates.global_position + 0), 0), coalesce(max(candidates.global_position + 0), 0)
              into from_gpos, to_gpos
              from candidates;

              return query #{compiled};
            end;
            $$;
          SQL
          conn.exec(compiled)
        end
      end
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
        pg_result = @query_strategy.exec_params(sql, [*attrs.values, id])
        raise(RecordNotFound.new('subscriptions', id)) if pg_result.ntuples == 0

        updated_attrs = pg_result.to_a.first
        unless updated_attrs['locked_by'] == locked_by
          # Subscription is force-locked by someone else. We have to roll back such transaction
          raise(WrongLockIdError.new(updated_attrs['set'], updated_attrs['name'], updated_attrs['locked_by']))
        end

        updated_attrs
      end

      deserialize(updated_attrs).slice(*attrs.keys)
    end

    # @param subscriptions_set_id [Integer] SubscriptionsSet#id
    # @param subscriptions_ids [Array<Integer>] Array of Subscription#id
    # @return [Hash<Integer => Time>]
    def ping_all(subscriptions_set_id, subscriptions_ids)
      sql = <<~SQL
        UPDATE subscriptions SET updated_at = $1 WHERE locked_by = $2 AND id = ANY($3::int[])
          RETURNING id, updated_at
      SQL
      pg_result = @query_strategy.exec_params(sql, [Time.now.utc, subscriptions_set_id, subscriptions_ids])
      pg_result.to_h do |attrs|
        [attrs['id'], attrs['updated_at']]
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

        @query_strategy.exec_params('UPDATE subscriptions SET locked_by = $1 WHERE id = $2', [lock_id, id])
      end
      lock_id
    end

    # @param id [Integer]
    # @return [void]
    def delete(id)
      function_name = QueryBuilders::SubscriptionEventsFiltering.new(id).to_table_name
      transaction_queries.transaction(:read_committed) do
        connection.with do |conn|
          conn.exec_params('delete from subscriptions where id = $1', [id])
          conn.exec("drop function if exists #{function_name}")
        end
      end
    end

    private

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end

    # @return [PgEventstore::LinksResolver]
    def links_resolver
      LinksResolver.new(connection, @query_strategy)
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
