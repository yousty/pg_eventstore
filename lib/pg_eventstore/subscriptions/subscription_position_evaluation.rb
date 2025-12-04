# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionPositionEvaluation
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

    def position_to_evaluate
      @mutex.synchronize { @position_to_evaluate }
    end

    def position_is_safe
      @mutex.synchronize { @position_is_safe }
    end

    def last_safe_position=(val)
      @mutex.synchronize { @last_safe_position = val }
    end

    def position_to_evaluate=(val)
      @mutex.synchronize { @position_to_evaluate = val }
    end

    def position_is_safe=(val)
      @mutex.synchronize { @position_is_safe = val }
    end

    def affected_tables
      if @stream_filters.empty? && @event_type_filters.empty?
        [Event::PRIMARY_TABLE_NAME]
      else
        partition_queries.partitions(@stream_filters, @event_type_filters, scope: :auto).map(&:table_name)
      end
    end

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
      rescue => e
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
