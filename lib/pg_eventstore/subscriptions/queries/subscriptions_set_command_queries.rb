# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionsSetCommandQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param subscriptions_set_id [Integer]
    # @param command_name [String]
    # @param data [Hash]
    # @return [PgEventstore::SubscriptionFeederCommands::Abstract]
    def find_or_create_by(subscriptions_set_id:, command_name:, data:)
      transaction_queries.transaction do
        find_by(subscriptions_set_id: subscriptions_set_id, command_name: command_name) ||
          create(subscriptions_set_id: subscriptions_set_id, command_name: command_name, data: data)
      end
    end

    # @param subscriptions_set_id [Integer]
    # @param command_name [String]
    # @return [PgEventstore::SubscriptionFeederCommands::Abstract, nil]
    def find_by(subscriptions_set_id:, command_name:)
      sql_builder =
        SQLBuilder.new.
          select('*').
          from('subscriptions_set_commands').
          where('subscriptions_set_id = ? AND name = ?', subscriptions_set_id, command_name)
      pg_result = connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end
      return if pg_result.ntuples.zero?

      deserialize(pg_result.to_a.first)
    end

    # @param subscriptions_set_id [Integer]
    # @param command_name [String]
    # @param data [Hash]
    # @return [PgEventstore::SubscriptionFeederCommands::Abstract]
    def create(subscriptions_set_id:, command_name:, data:)
      sql = <<~SQL
        INSERT INTO subscriptions_set_commands (name, subscriptions_set_id, data) 
          VALUES ($1, $2, $3)
          RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, [command_name, subscriptions_set_id, data])
      end
      deserialize(pg_result.to_a.first)
    end

    # @param subscriptions_set_id [Integer]
    # @return [Array<PgEventstore::SubscriptionFeederCommands::Abstract>]
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
    # @return [PgEventstore::SubscriptionFeederCommands::Base]
    def deserialize(hash)
      attrs = hash.transform_keys(&:to_sym)
      SubscriptionFeederCommands.command_class(attrs[:name]).new(**attrs)
    end

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end
  end
end
