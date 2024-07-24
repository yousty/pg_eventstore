# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionCommandQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param subscription_id [Integer]
    # @param subscriptions_set_id [Integer]
    # @param command_name [String]
    # @param data [Hash]
    # @return [PgEventstore::SubscriptionRunnerCommands::Base]
    def find_or_create_by(subscription_id:, subscriptions_set_id:, command_name:, data:)
      transaction_queries.transaction do
        find_by(subscription_id: subscription_id, subscriptions_set_id: subscriptions_set_id, command_name: command_name) ||
          create(subscription_id: subscription_id, subscriptions_set_id: subscriptions_set_id, command_name: command_name, data: data)
      end
    end

    # @param subscription_id [Integer]
    # @param subscriptions_set_id [Integer]
    # @param command_name [String]
    # @return [PgEventstore::SubscriptionRunnerCommands::Base, nil]
    def find_by(subscription_id:, subscriptions_set_id:, command_name:)
      sql_builder =
        SQLBuilder.new.
          select('*').
          from('subscription_commands').
          where(
            'subscription_id = ? AND subscriptions_set_id = ? AND name = ?',
            subscription_id, subscriptions_set_id, command_name
          )
      pg_result = connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end
      return if pg_result.ntuples.zero?

      deserialize(pg_result.to_a.first)
    end

    # @param subscription_id [Integer]
    # @param subscriptions_set_id [Integer]
    # @param command_name [String]
    # @param data [Hash]
    # @return [PgEventstore::SubscriptionRunnerCommands::Base]
    def create(subscription_id:, subscriptions_set_id:, command_name:, data:)
      sql = <<~SQL
        INSERT INTO subscription_commands (name, subscription_id, subscriptions_set_id, data) 
          VALUES ($1, $2, $3, $4)
          RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(sql, [command_name, subscription_id, subscriptions_set_id, data])
      end
      deserialize(pg_result.to_a.first)
    end

    # @param subscription_ids [Array<Integer>]
    # @param subscriptions_set_id [Integer]
    # @return [Array<PgEventstore::SubscriptionRunnerCommands::Base>]
    def find_commands(subscription_ids, subscriptions_set_id:)
      return [] if subscription_ids.empty?

      sql = subscription_ids.size.times.map do
        "?"
      end.join(", ")
      sql_builder =
        SQLBuilder.new.select('*').
          from('subscription_commands').
          where("subscription_id IN (#{sql})", *subscription_ids).
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
        conn.exec_params('DELETE FROM subscription_commands WHERE id = $1', [id])
      end
    end

    private

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end

    # @param hash [Hash]
    # @return [PgEventstore::SubscriptionRunnerCommands::Base]
    def deserialize(hash)
      attrs = hash.transform_keys(&:to_sym)
      SubscriptionRunnerCommands.command_class(attrs[:name]).new(**attrs)
    end
  end
end
