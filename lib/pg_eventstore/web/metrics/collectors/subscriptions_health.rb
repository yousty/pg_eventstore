# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      module Collectors
        # Liveness and error state of each reported subscription.
        #
        # The state column alone can not be trusted: a subscription killed without a graceful shutdown keeps
        # state "running" and its lock forever. heartbeat_age_seconds is the discriminator - a subscription is
        # really running only while its heartbeat stays below
        # {PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL}.
        class SubscriptionsHealth < Base
          # @return [Array<PgEventstore::Web::Metrics::MetricFamily>]
          def call
            state = MetricFamily.new(
              name: 'pg_eventstore_subscription_state',
              type: 'gauge',
              help: 'Last recorded state of the subscription. May be stale - correlate with ' \
                    'pg_eventstore_subscription_heartbeat_age_seconds.'
            )
            locked = MetricFamily.new(
              name: 'pg_eventstore_subscription_locked',
              type: 'gauge',
              help: 'Whether the subscription is locked by a subscriptions set.'
            )
            heartbeat_age = MetricFamily.new(
              name: 'pg_eventstore_subscription_heartbeat_age_seconds',
              type: 'gauge',
              help: 'Seconds since the subscription row was last touched by its runner. A locked subscription ' \
                    'with a stale heartbeat is a dead process that did not shut down gracefully.'
            )
            restarts = MetricFamily.new(
              name: 'pg_eventstore_subscription_restarts_total',
              type: 'counter',
              help: 'Number of times the subscription was restarted after a failure.'
            )
            last_error_age = MetricFamily.new(
              name: 'pg_eventstore_subscription_last_error_age_seconds',
              type: 'gauge',
              help: 'Seconds since the last error occurred. Absent when the subscription never failed.'
            )
            subscription_rows.each do |row|
              labels = subscription_labels(row)
              state.add_sample(labels: labels.merge(state: row['state']), value: 1)
              locked.add_sample(labels:, value: row['locked'])
              heartbeat_age.add_sample(labels:, value: row['heartbeat_age_seconds'])
              restarts.add_sample(labels:, value: row['restart_count'])
              last_error_age.add_sample(labels:, value: row['last_error_age_seconds']) if row['last_error_age_seconds']
            end
            [state, locked, heartbeat_age, restarts, last_error_age]
          end

          private

          # @return [Array<Hash>]
          def subscription_rows
            builder = subscriptions_sql_builder
            builder.select(<<~SQL)
              s.set,
              s.name,
              s.state,
              (s.locked_by is not null)::int as locked,
              extract(epoch from ((now() at time zone 'utc') - s.updated_at))::float8 as heartbeat_age_seconds,
              s.restart_count,
              case when s.last_error_occurred_at is not null
                   then extract(epoch from ((now() at time zone 'utc') - s.last_error_occurred_at))::float8
              end as last_error_age_seconds
            SQL
            with_safe_conn do |conn|
              conn.exec_params(*builder.to_exec_params)
            end
          end
        end
      end
    end
  end
end
