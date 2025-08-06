# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionsSetQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param attrs [Hash]
    # @return [Array<Hash>]
    def find_all(attrs)
      builder = SQLBuilder.new.select('*').from('subscriptions_set').order('name ASC, id ASC')
      attrs.each do |attr, val|
        builder.where("#{attr} = ?", val)
      end

      pg_result = connection.with do |conn|
        conn.exec_params(*builder.to_exec_params)
      end
      pg_result.to_a.map(&method(:deserialize))
    end

    # @param name [String, nil]
    # @param state [String]
    # @return [Array<Hash>]
    def find_all_by_subscription_state(name:, state:)
      builder = SQLBuilder.new.select('subscriptions_set.*').from('subscriptions_set')
      builder.join('JOIN subscriptions ON subscriptions.locked_by = subscriptions_set.id')
      builder.order('subscriptions_set.name ASC, subscriptions_set.id ASC')
      builder.where('subscriptions_set.name = ? and subscriptions.state = ?', name, state)
      builder.group('subscriptions_set.id')
      pg_result = connection.with do |conn|
        conn.exec_params(*builder.to_exec_params)
      end
      pg_result.to_a.map(&method(:deserialize))
    end

    # @return [Array<String>]
    def set_names
      builder = SQLBuilder.new.select('name').from('subscriptions_set').group('name').order('name ASC')

      raw_set = connection.with do |conn|
        conn.exec_params(*builder.to_exec_params)
      end
      raw_set.map { |attrs| attrs['name'] }
    end

    # The same as #find_all, but returns first result
    # @return [Hash, nil]
    def find_by(...)
      find_all(...).first
    end

    # @param id [Integer]
    # @return [Hash]
    # @raise [PgEventstore::RecordNotFound]
    def find!(id)
      find_by(id: id) || raise(RecordNotFound.new('subscriptions_set', id))
    end

    # @param attrs [Hash]
    # @return [Hash]
    def create(attrs)
      sql = <<~SQL
        INSERT INTO subscriptions_set (#{attrs.keys.join(', ')})#{' '}
          VALUES (#{Utils.positional_vars(attrs.values)})#{' '}
          RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, attrs.values)
      end
      deserialize(pg_result.to_a.first)
    end

    # @param id [Integer]
    # @param attrs [Hash]
    # @return [Hash]
    def update(id, attrs)
      attrs = { updated_at: Time.now.utc }.merge(attrs)
      attrs_sql = attrs.keys.map.with_index(1) do |attr, index|
        "#{attr} = $#{index}"
      end.join(', ')
      sql = <<~SQL
        UPDATE subscriptions_set SET #{attrs_sql} WHERE id = $#{attrs.keys.size + 1} RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, [*attrs.values, id])
      end
      raise(RecordNotFound.new('subscriptions_set', id)) if pg_result.ntuples == 0

      deserialize(pg_result.to_a.first)
    end

    # @param id [Integer]
    # @return [void]
    def delete(id)
      connection.with do |conn|
        conn.exec_params('DELETE FROM subscriptions_set WHERE id = $1', [id])
      end
    end

    private

    # @param hash [Hash]
    # @return [Hash]
    def deserialize(hash)
      hash.transform_keys(&:to_sym)
    end

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end
  end
end
