# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionServiceQueries
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

    # @return [Integer, nil] number of updated records
    def assign_subscription_position
      transaction_queries.transaction(:read_committed) do
        connection.with do |conn|
          locked = conn.exec_params(
            'select pg_try_advisory_xact_lock($1::bigint) as locked',
            [INDEXES_UPDATE_LOCK_ID]
          ).first['locked']
          return unless locked

          conn.exec_params(<<~SQL, [MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION]).cmd_tuples
            WITH fresh_events
                     AS MATERIALIZED (SELECT global_position,
                                             nextval('events_subscription_position_seq'::regclass) AS
                                                 subscription_position
                                      FROM events_global_index
                                      WHERE subscription_position IS NULL
                                      ORDER BY global_position
                                      LIMIT $1 FOR UPDATE)
            UPDATE events_global_index
            SET subscription_position = fresh_events.subscription_position
            FROM fresh_events
            WHERE events_global_index.global_position = fresh_events.global_position
          SQL
        end
      end
    end

    # @return [Integer, nil]
    def max_subscription_position
      builder = SQLBuilder.new.from(QueryBuilders::EventsGlobalIndexFiltering::PRIMARY_TABLE_NAME)
      builder.select('max(subscription_position) as max_subscription_position')
      builder.where('subscription_position is not null')
      connection.with do |conn|
        conn.exec_params(*builder.to_exec_params).first['max_subscription_position']
      end
    end

    private

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end
  end
end
