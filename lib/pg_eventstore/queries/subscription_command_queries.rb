# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionCommandQueries
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param subscription_id [Integer]
    # @param command_name [String]
    # @return [Hash, nil]
    def find_by(subscription_id:, command_name:)
      sql_builder =
        SQLBuilder.new.
          select('*').
          from('subscription_commands').
          where('subscription_id = ? AND name = ?', subscription_id, command_name)
      pg_result = connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end
      return if pg_result.ntuples.zero?

      deserialize(pg_result.to_a.first)
    end

    # @param subscription_id [Integer]
    # @param command_name [String]
    # @return [Hash]
    def create_by(subscription_id:, command_name:)
      sql = <<~SQL
        INSERT INTO subscription_commands (name, subscription_id) 
          VALUES ($1, $2)
          RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, [command_name, subscription_id])
      end
      deserialize(pg_result.to_a.first)
    end

    # @param subscription_ids [Array<Integer>]
    # @return [Array<Hash>]
    def find_commands(subscription_ids)
      return [] if subscription_ids.empty?

      sql = subscription_ids.size.times.map do
        "?"
      end.join(", ")
      sql_builder =
        SQLBuilder.new.select('*').
          from('subscription_commands').
          where("subscription_id IN (#{sql})", *subscription_ids).
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
        conn.exec_params('DELETE FROM subscription_commands WHERE id = $1', [id])
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
