# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      module Collectors
        # How far behind each alive subscription is.
        #
        # Subscription#current_position is a checkpoint in subscription_position units - the dense, commit-ordered
        # sequence assigned via the event_subscription_positions table - NOT in events.global_position units (that
        # sequence contains gaps and runs ahead). Lag is therefore measured against the subscription positions
        # frontier, never against the global position head.
        #
        # - lag_events: how many events the subscription has not checked yet.
        # - lag_seconds: age of the oldest event the subscription has not checked yet; 0 when fully caught up.
        #   Rows of event_subscription_positions are pruned by retention, so for a subscription that is very far
        #   behind this reports the age of the oldest *retained* unprocessed event - a lower bound. Trust lag_events
        #   when the two disagree.
        #
        # The frontier only advances while at least one subscriptions process runs its position worker. When every
        # subscriptions process is down, lag freezes - that situation is caught by the heartbeat metric of the
        # health collector, not by this one.
        class SubscriptionsLatency < Base
          # @return [Array<PgEventstore::Web::Metrics::MetricFamily>]
          def call
            lag_events = MetricFamily.new(
              name: 'pg_eventstore_subscription_lag_events',
              type: 'gauge',
              help: 'Number of events between the subscription checkpoint and the subscription positions frontier.'
            )
            lag_seconds = MetricFamily.new(
              name: 'pg_eventstore_subscription_lag_seconds',
              type: 'gauge',
              help: 'Age in seconds of the oldest retained event the subscription has not processed yet. ' \
                    '0 when caught up.'
            )
            subscription_rows.each do |row|
              labels = subscription_labels(row)
              lag_events.add_sample(labels:, value: row['lag_events'])
              lag_seconds.add_sample(labels:, value: row['lag_seconds'])
            end
            [lag_events, lag_seconds, *store_families]
          end

          private

          # @return [Array<Hash>]
          def subscription_rows
            rows(<<~SQL)
              with frontier as (
                select case when is_called then last_value else 0 end as position
                from event_subscription_positions_subscription_position_seq
              )
              select s.set, s.name,
                     greatest(frontier.position - coalesce(s.current_position, 0), 0) as lag_events,
                     coalesce(
                       extract(epoch from ((now() at time zone 'utc') - next_event.created_at)), 0
                     )::float8 as lag_seconds
              from subscriptions s
              cross join frontier
              left join lateral (
                select e.created_at
                from event_subscription_positions esp
                join events e on e.global_position = esp.global_position
                where esp.subscription_position > coalesce(s.current_position, 0)
                order by esp.subscription_position
                limit 1
              ) next_event on true
              where #{liveness_condition}
              order by s.set, s.name
            SQL
          end

          # @return [Array<PgEventstore::Web::Metrics::MetricFamily>]
          def store_families
            row = rows(<<~SQL).first
              select
                (
                  select case when is_called then last_value else 0 end
                  from event_subscription_positions_subscription_position_seq
                ) as frontier_position,
                (
                  select case when is_called then last_value else 0 end
                  from events_global_position_seq
                ) as head_global_position
            SQL
            frontier = MetricFamily.new(
              name: 'pg_eventstore_store_frontier_position',
              type: 'gauge',
              help: 'Latest assigned subscription position. Subscription checkpoints are measured against this.'
            )
            frontier.add_sample(labels: {}, value: row['frontier_position'])
            head = MetricFamily.new(
              name: 'pg_eventstore_store_head_global_position',
              type: 'gauge',
              help: 'Latest value of the events global position sequence. Contains gaps; do not compare ' \
                    'subscription checkpoints against it.'
            )
            head.add_sample(labels: {}, value: row['head_global_position'])
            [frontier, head]
          end
        end
      end
    end
  end
end
