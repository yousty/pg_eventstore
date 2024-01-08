# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionsSetCommandQueries
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param subscriptions_set_id [Integer]
    # @param command_name [String]
    # @return [Hash, nil]
    def find_by(subscriptions_set_id:, command_name:)
      sql_builder =
        SQLBuilder.new.
          select('*').
          from('subscriptions_set_commands').
          where('subscriptions_set_id = ? AND command_name = ?', subscriptions_set_id, command_name)
      pg_result = connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end
      return if pg_result.ntuples.zero?

      deserialize(pg_result.to_a.first)
    end

    # @param subscriptions_set_id [Integer]
    # @param command_name [String]
    # @return [Hash]
    def create_by(subscriptions_set_id:, command_name:)
      sql = <<~SQL
        INSERT INTO subscriptions_set_commands (name, subscriptions_set_id) 
          VALUES ($1, $2)
          RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, [command_name, subscriptions_set_id])
      end
      deserialize(pg_result.to_a.first)
    end

    # @param subscriptions_set_id [Integer]
    # @return [Array<Hash>]
    def find_commands(subscriptions_set_id)
      sql_builder =
        SQLBuilder.new.select('*').
          from('subscriptions_set_commands').
          where("subscriptions_set_id = ?", subscriptions_set_id).
          order('id ASC')
      pg_result = connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end
      pg_result.to_a.map(&method(:deserialize))
    end

    # @param id [Integer]
    # @return [void]
    def delete(id)
      connection.with do |conn|
        conn.exec_params('DELETE FROM subscriptions_set_commands WHERE id = $1', [id])
      end
    end

    private

    # @param hash [Hash]
    # @return [Hash]
    def deserialize(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
