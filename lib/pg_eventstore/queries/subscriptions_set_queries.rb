# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionsSetQueries
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param attrs [Hash]
    # @return [Hash]
    def create(attrs)
      sql = <<~SQL
        INSERT INTO subscriptions_set (#{attrs.keys.join(', ')}) 
          VALUES (#{Utils.positional_vars(attrs.values)}) 
          RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, attrs.values)
      end
      pg_result.to_a.first.transform_keys(&:to_sym)
    end

    # @param subscriptions_set [PgEventstore::SubscriptionsSet]
    # @param attrs [Hash]
    def update(subscriptions_set, attrs)
      attrs = { updated_at: Time.now.utc }.merge(attrs)
      attrs_sql = attrs.keys.map.with_index(1) do |attr, index|
        "#{attr} = $#{index}"
      end.join(', ')
      sql = <<~SQL
        UPDATE subscriptions_set SET #{attrs_sql} WHERE id = $#{attrs.keys.size + 1} RETURNING #{attrs.keys.join(', ')}
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, [*attrs.values, subscriptions_set.id])
      end
      subscriptions_set.assign_attributes(pg_result.to_a.first)
    end

    def delete(id)
      connection.with do |conn|
        conn.exec_params('DELETE FROM subscriptions_set WHERE id = $1', [id])
      end
    end
  end
end
