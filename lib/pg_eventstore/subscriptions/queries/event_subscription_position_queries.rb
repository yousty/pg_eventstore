# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventSubscriptionPositionQueries
    # Max number of events_global_index records to update
    # @return [Integer]
    MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION = 100_000
    # @return [Integer]
    INDEXES_UPDATE_LOCK_ID = 462_315_339_855_922

    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param raw_events [Array<Hash>]
    # @return [void]
    def create_unprocessed_positions(raw_events)
      values = raw_events.map { "(#{_1['global_position']})" }.join(', ')
      connection.with do |conn|
        conn.exec(<<~SQL)
          INSERT INTO event_subscription_positions_unprocessed ("global_position") VALUES #{values};
        SQL
      end
    end

    # @param events [Array<PgEventstore::Event>]
    # @return [Hash<Integer, Integer>]
    def subscription_positions_from_db(events)
      filtering = QueryBuilders::EventSubscriptionPositionsFiltering.new
      filtering.by_global_positions(events.map(&:global_position))
      connection.with do |conn|
        conn.exec_params(*filtering.to_exec_params).to_h do |attrs|
          [attrs['global_position'], attrs['subscription_position']]
        end
      end
    end

    # @return [Integer, nil]
    def max_subscription_position
      filtering = QueryBuilders::EventSubscriptionPositionsFiltering.new
      filtering.max_subscription_position
      connection.with do |conn|
        conn.exec_params(*filtering.to_exec_params).first['max_subscription_position']
      end
    end

    # @return [Integer, nil] number of updated records
    def assign_subscription_position
      transaction_queries.transaction(:read_committed) do
        connection.with do |conn|
          locked = conn.exec_params(
            'select pg_try_advisory_xact_lock($1::bigint) as locked',
            [INDEXES_UPDATE_LOCK_ID]
          ).first['locked']
          return unless locked

          new_positions = conn.exec_params(<<~SQL, [MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION])
            select global_position
            from event_subscription_positions_unprocessed
            order by global_position
            limit $1
          SQL
          return 0 if new_positions.ntuples == 0

          affected_positions = new_positions.map { _1['global_position'] }
          new_positions_values = affected_positions.map { "(#{_1})" }.join(', ')

          conn.exec(<<~SQL)
            insert into event_subscription_positions (global_position) values #{new_positions_values}
          SQL
          affected_positions = new_positions.map { _1['global_position'] }
          conn.exec(<<~SQL).cmd_tuples
            delete from event_subscription_positions_unprocessed
            where global_position in (#{affected_positions.join(',')})
          SQL
        end
      end
    end

    private

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end
  end
end
