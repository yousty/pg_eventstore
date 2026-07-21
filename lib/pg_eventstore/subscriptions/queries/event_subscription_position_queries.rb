# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventSubscriptionPositionQueries
    # Max number of events_global_index records to update
    # @return [Integer]
    MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION = 100_000
    # @return [Integer]
    ASSIGN_SUBSCRIPTION_POSITIONS_LOCK_ID = 462_315_339_855_922
    # @return [Integer]
    REINDEX_PERIOD = 24 * 60 * 60 # 1 day
    # Do not reindex if index size is under this value
    # @return [Integer]
    UNPROCESSED_POSITIONS_INDEX_SIZE_THRESHOLD = 500 * 1_024 * 1_024 # 500 MB
    # @return [String]
    UNPROCESSED_POSITIONS_INDEX_NAME = 'idx_event_subscription_positions_unprocessed_gposition'
    # @return [Integer]
    UNPROCESSED_POSITIONS_LOCK_EXPIRES_IN = 5 * 60 # 5 minutes

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
            [ASSIGN_SUBSCRIPTION_POSITIONS_LOCK_ID]
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

    # There is no concept of periodic maintenance tasks yet. Simply hardcode it for now and abstract when needed.
    # @return [Time, nil]
    def reindex_unprocessed_positions
      task_name = 'reindex_unprocessed_positions'
      task = connection.with do |conn|
        conn.exec_params(
          'select * from maintenance_tasks where task_name = $1',
          [task_name]
        ).first
      end
      if task && task['performed_at'] && task['performed_at'] + REINDEX_PERIOD > Time.now
        return task['performed_at'] + REINDEX_PERIOD
      end

      if task
        locked =
          if task['locked_at']
            if task['locked_at'] + UNPROCESSED_POSITIONS_LOCK_EXPIRES_IN > Time.now
              # the task is locked by someone else. Retry later
              return task['locked_at'] + UNPROCESSED_POSITIONS_LOCK_EXPIRES_IN
            end

            connection.with do |conn|
              conn.exec_params(
                'update maintenance_tasks set locked_at = $1 where task_name = $2 and locked_at = $3',
                [Time.now.utc, task_name, task['locked_at']]
              )
            end.cmd_tuples == 1
          else
            connection.with do |conn|
              conn.exec_params(
                'update maintenance_tasks set locked_at = $1 where task_name = $2 and locked_at is null',
                [Time.now.utc, task_name]
              )
            end.cmd_tuples == 1
          end
        return unless locked
      else
        connection.with do |conn|
          conn.exec_params(
            'insert into maintenance_tasks (task_name, locked_at) values ($1, $2) returning *',
            [task_name, Time.now.utc]
          ).first
        end
      end

      index_name = UNPROCESSED_POSITIONS_INDEX_NAME
      if index_size(index_name) > UNPROCESSED_POSITIONS_INDEX_SIZE_THRESHOLD
        connection.with do |conn|
          conn.exec("reindex index concurrently #{index_name}")
        end
      end
      connection.with do |conn|
        conn.exec_params(
          'update maintenance_tasks set performed_at = $1, locked_at = null where task_name = $2',
          [Time.now.utc, task_name]
        )
      end
      Time.now.utc + REINDEX_PERIOD
    rescue PG::UniqueViolation
      # concurrent process has created the record before us
    end

    # @param index_name [String]
    # @return [Integer]
    def index_size(index_name)
      connection.with do |conn|
        conn.exec_params(
          'select pg_relation_size(c.oid) as size from pg_class c where c.relname = $1',
          [index_name]
        ).first['size'] || 0
      end
    end

    private

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end
  end
end
