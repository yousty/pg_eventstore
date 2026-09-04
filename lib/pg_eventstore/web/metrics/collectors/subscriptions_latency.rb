# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      module Collectors
        # How far behind each subscription is.
        #
        # A subscription checkpoint is measured in the same units as the subscription positions frontier, not in
        # events.global_position units - the global position sequence contains gaps and runs ahead of the frontier,
        # so comparing a checkpoint against it over-reports by orders of magnitude. Lag is therefore always measured
        # against the frontier.
        #
        # - lag_events: how much of the store the subscription still has to walk through before it reaches the
        #   frontier - that is, before it starts processing newly appended events.
        # - lag_seconds: age of the oldest event the subscription has not processed yet; 0 when caught up.
        #
        # The frontier only advances while at least one subscriptions process is running. When they are all down lag
        # stops growing - that situation is reported by the heartbeat metric of the health collector, not here.
        class SubscriptionsLatency < Base
          # @return [Array<PgEventstore::Web::Metrics::MetricFamily>]
          def call
            lag_events = MetricFamily.new(
              name: 'pg_eventstore_subscription_lag_events',
              type: 'gauge',
              help: 'How many events the subscription still has to catch up on before it reaches the edge of the ' \
                    '"all" stream.'
            )
            lag_seconds = MetricFamily.new(
              name: 'pg_eventstore_subscription_lag_seconds',
              type: 'gauge',
              help: 'Age in seconds of the oldest event the subscription has not processed yet. 0 when caught up.'
            )
            frontier_position, head_global_position = *positions
            rows = subscription_rows(frontier_position)
            created_at_by_position = resolve_created_at(rows)
            now = Time.now.utc
            rows.each { add_samples(_1, created_at_by_position, now, lag_events, lag_seconds) }
            [lag_events, lag_seconds, *store_families(frontier_position, head_global_position)]
          end

          private

          # @param row [Hash]
          # @param created_at_by_position [Hash<Integer => Time>]
          # @param now [Time]
          # @param lag_events [PgEventstore::Web::Metrics::MetricFamily]
          # @param lag_seconds [PgEventstore::Web::Metrics::MetricFamily]
          # @return [void]
          def add_samples(row, created_at_by_position, now, lag_events, lag_seconds)
            labels = subscription_labels(row)
            lag_events.add_sample(labels:, value: row['lag_events'])
            position = row['event_global_position']
            # Caught up - nothing is left to process, so there is no unprocessed event to age. Deliberately a float:
            # the metric is seconds everywhere else, and a gauge that renders as "0" here and "12.5" there is a wart.
            return lag_seconds.add_sample(labels:, value: 0.0) if position.nil?

            created_at = created_at_by_position[position]
            # An unprocessed position whose event no longer exists (the event or its stream was deleted). Reporting 0
            # would read as "caught up", the opposite of the truth, so report nothing - lag_events still carries the
            # backlog.
            return if created_at.nil?

            lag_seconds.add_sample(labels:, value: [(now - created_at).to_f, 0].max)
          end

          # One index range scan per subscription over idx_event_subscription_positions_sposition_n_gposition. The
          # cost does not grow with the size of the backlog: the oldest unprocessed position is taken with
          # "order by subscription_position limit 1" rather than by aggregating over the whole backlog.
          # @param frontier_position [Integer]
          # @return [Array<Hash>]
          def subscription_rows(frontier_position)
            builder = subscriptions_sql_builder
            builder.select(<<~SQL)
              s.set,
              s.name,
              greatest(#{frontier_position} - coalesce(s.current_position, 0), 0) as lag_events,
              next_event.global_position as event_global_position,
              next_event.event_type_partition_id as event_type_partition_id
            SQL
            builder.join(<<~SQL)
              left join lateral (
                  select egi.global_position, egi.event_type_partition_id
                  from event_subscription_positions esp
                  join events_global_index egi on egi.global_position = esp.global_position
                  where esp.subscription_position > coalesce(s.current_position, 0)
                  order by esp.subscription_position
                  limit 1
                ) next_event on true
            SQL
            with_safe_conn do |conn|
              conn.exec_params(*builder.to_exec_params)
            end
          end

          # Resolves the creation time of every subscription's oldest unprocessed event.
          #
          # The events table is partitioned, and these events are known only by global position - which is not the
          # partition key. Looking them up in events by global position alone would have to visit every partition and
          # lock all of them, which stops being viable long before a store reaches five figures of partitions.
          # events_global_index records the partition of each event, so the read API can resolve them partition-wise
          # instead.
          # @param subscription_rows [Array<Hash>]
          # @return [Hash<Integer => Time>]
          def resolve_created_at(subscription_rows)
            indexes = subscription_rows.filter_map do |attrs|
              next if attrs['event_global_position'].nil?

              EventGlobalIndex::ReadApiRepr.new(
                global_position: attrs['event_global_position'],
                event_type_partition_id: attrs['event_type_partition_id']
              )
            end
            return {} if indexes.empty?

            resolved = events_global_index_queries.resolve_indexes(indexes, resolve_link_tos: false)
            resolved.to_h { [_1['global_position'], _1['created_at']] }
          end

          # @return [PgEventstore::EventsGlobalIndexQueries]
          def events_global_index_queries
            EventsGlobalIndexQueries.new(connection, QueryStrategy::Foreground.new(connection))
          end

          # @param frontier_position [Integer]
          # @param head_global_position [Integer]
          # @return [Array<PgEventstore::Web::Metrics::MetricFamily>]
          def store_families(frontier_position, head_global_position)
            frontier = MetricFamily.new(
              name: 'pg_eventstore_store_frontier_position',
              type: 'gauge',
              help: 'Latest assigned subscription position. Subscription checkpoints are measured against this.'
            )
            frontier.add_sample(labels: {}, value: frontier_position)
            head = MetricFamily.new(
              name: 'pg_eventstore_store_head_global_position',
              type: 'gauge',
              help: 'Global position of the newest event in the store. Contains gaps; do not compare subscription ' \
                    'checkpoints against it.'
            )
            head.add_sample(labels: {}, value: head_global_position)
            [frontier, head]
          end

          # @return [Array[Integer]]
          def positions
            res = with_safe_conn do |conn|
              conn.exec(<<~SQL)
                select
                  (select coalesce(max(subscription_position), 0) from event_subscription_positions)
                    as frontier_position,
                  (select coalesce(max(global_position), 0) from events_global_index) as head_global_position
              SQL
            end
            res.first.values_at('frontier_position', 'head_global_position')
          end
        end
      end
    end
  end
end
