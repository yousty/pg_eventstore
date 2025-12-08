# frozen_string_literal: true

module PgEventstore
  # When subscription pulls events at the edge of the events list and several events arrives concurrently - there is a
  # chance some events will never be picked. Example:
  # - event1 has been assigned global_position#9
  # - event2 has been assigned global_position#10
  # - event1 and event2 are currently in concurrent transactions, but those transactions does not block each other
  # - transaction holding event2 commits first
  # - a subscription picks event2 and sets next position to 11
  # - transaction holding event1 commits
  # Illustration:
  #   Time → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → → →
  #
  #   T1:  BEGIN
  #          INSERT INTO events(...);
  #        --------------------global_position#9------------------->
  #       COMMIT
  #   T2:       BEGIN
  #               INSERT INTO events(...);
  #             --------------global_position#10-------->
  #             COMMIT
  #   Query events:                                       SELECT * FROM event WHERE global_position >= 8
  #                                                       --------------Picks #8, #10, but never #9-------->
  #
  # To solve this problem we can:
  # 1. pause events fetching for the subscription
  # 2. fetch latest global position that matches subscription's filter
  # 3. wait for all currently running transactions that affects on the subscription to finish
  # 4. unpause events fetching and use this position as a right hand limiter, because we can now confidently say there
  #   are no uncommited events that would be lost otherwise
  # This class is responsible for the step 2 and step 3, and persists the last safe position to be used in step 4.
  # @!visibility private
  class SubscriptionPositionEvaluation
    # Determines how often to check the list of currently running transactions
    # @return [Float]
    TRANSACTIONS_STATUS_REFRESH_INTERVAL = 0.05 # seconds
    private_constant :TRANSACTIONS_STATUS_REFRESH_INTERVAL

    # @param config_name [Symbol]
    # @param filter_options [Hash]
    def initialize(config_name:, filter_options:)
      @config_name = config_name
      @stream_filters = QueryBuilders::PartitionsFiltering.extract_streams_filter(filter: filter_options)
      @event_type_filters = QueryBuilders::PartitionsFiltering.extract_event_types_filter(filter: filter_options)
      @position_to_evaluate = nil
      @position_is_safe = nil
      @last_safe_position = nil
      @runner = nil
      @relation_ids_cache = {}
      @mutex = Mutex.new
    end

    # @param position_to_evaluate [Integer]
    # @return [self]
    def evaluate(position_to_evaluate)
      unless self.position_to_evaluate == position_to_evaluate
        stop_evaluation
        self.position_to_evaluate = position_to_evaluate
        calculate_safe_position
      end
      self
    end

    # @return [Boolean]
    def safe?
      @mutex.synchronize { @position_is_safe } || false
    end

    # @return [Integer, nil]
    def last_safe_position
      @mutex.synchronize { @last_safe_position }
    end

    # @return [Thread, nil] a runner who is being stopped if any
    def stop_evaluation
      _stop_evaluation(@runner)
    end

    private

    # @param runner [Thread, nil]
    # @return [Thread, nil]
    def _stop_evaluation(runner)
      runner&.exit
      self.position_is_safe = nil
      self.last_safe_position = nil
      self.position_to_evaluate = nil
    end

    # @return [Integer, nil]
    def position_to_evaluate
      @mutex.synchronize { @position_to_evaluate }
    end

    # @return [Boolean, nil]
    def position_is_safe
      @mutex.synchronize { @position_is_safe }
    end

    # @param val [Integer, nil]
    # @return [Integer, nil]
    def last_safe_position=(val)
      @mutex.synchronize { @last_safe_position = val }
    end

    # @param val [Integer, nil]
    # @return [Integer, nil]
    def position_to_evaluate=(val)
      @mutex.synchronize { @position_to_evaluate = val }
    end

    # @param val [Boolean, nil]
    # @return [Boolean, nil]
    def position_is_safe=(val)
      @mutex.synchronize { @position_is_safe = val }
    end

    # @return [Array<String>]
    def affected_tables
      if @stream_filters.empty? && @event_type_filters.empty?
        [Event::PRIMARY_TABLE_NAME]
      else
        partition_queries.partitions(@stream_filters, @event_type_filters, scope: :auto).map(&:table_name)
      end
    end

    # @return [void]
    def calculate_safe_position
      @runner = Thread.new do
        tables_to_track = affected_tables
        update_relation_ids_cache(tables_to_track)
        safe_position = service_queries.max_global_position(tables_to_track)
        trx_ids = transaction_queries.transaction do
          service_queries.relation_transaction_ids(@relation_ids_cache.values)
        end

        loop do
          transactions_in_progress = service_queries.transactions_in_progress?(
            relation_ids: @relation_ids_cache.values, transaction_ids: trx_ids
          )
          break unless transactions_in_progress

          sleep TRANSACTIONS_STATUS_REFRESH_INTERVAL
        end
        @mutex.synchronize do
          if safe_position >= @position_to_evaluate
            # We progressed forward. New position can be persisted
            @last_safe_position = safe_position
            @position_is_safe = true
          else
            # safe_position is less than the current position to fetch the events from. This means that no new events
            # are present at this point. We will need to re-evaluate the safe position during next attempts. Until that
            # we can't progress.
            @position_to_evaluate = nil
          end
        end
      rescue
        # Clean up the state immediately in case of error
        _stop_evaluation(nil)
      end
    end

    # @param tables_to_track [Array<String>]
    # @return [void]
    def update_relation_ids_cache(tables_to_track)
      missing_relation_ids = tables_to_track - @relation_ids_cache.keys
      deleted_relations = @relation_ids_cache.keys - tables_to_track
      @relation_ids_cache = @relation_ids_cache.except(*deleted_relations)
      return if missing_relation_ids.empty?

      @relation_ids_cache.merge!(service_queries.relation_ids_by_names(missing_relation_ids))
    end

    # @return [PgEventstore::PartitionQueries]
    def partition_queries
      PartitionQueries.new(connection)
    end

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end

    # @return [PgEventstore::ServiceQueries]
    def service_queries
      ServiceQueries.new(connection)
    end

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(@config_name)
    end
  end
end
