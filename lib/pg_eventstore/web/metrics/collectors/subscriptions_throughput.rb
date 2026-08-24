# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      module Collectors
        # Processing volume and speed of each reported subscription.
        #
        # Two deliberately different numbers:
        # - processed_events_total is a counter; rate() over it gives the actual current throughput and correctly
        #   drops to 0 when no matching events arrive.
        # - capacity_events_per_second derives from the average handler execution time of the last
        #   {PgEventstore::SubscriptionHandlerPerformance::TIMINGS_TO_KEEP} processed events - whenever they
        #   happened. It answers "how fast can this handler go when fed", is sticky while the subscription is idle
        #   and must not be read as current throughput.
        class SubscriptionsThroughput < Base
          # @return [Array<PgEventstore::Web::Metrics::MetricFamily>]
          def call
            processed = MetricFamily.new(
              name: 'pg_eventstore_subscription_processed_events_total',
              type: 'counter',
              help: 'Total number of events processed by the subscription. Use rate() for current throughput.'
            )
            capacity = MetricFamily.new(
              name: 'pg_eventstore_subscription_capacity_events_per_second',
              type: 'gauge',
              help: 'Average processing speed over the last few processed events, whenever they happened. ' \
                    'Sticky while idle - this is handler capacity, not current throughput.'
            )
            subscription_rows.each do |row|
              labels = subscription_labels(row)
              processed.add_sample(labels:, value: row['total_processed_events'])
              capacity.add_sample(labels:, value: row['capacity_eps']) if row['capacity_eps']
            end
            [processed, capacity]
          end

          private

          # @return [Array<Hash>]
          def subscription_rows
            rows(<<~SQL, sets_params)
              select s.set, s.name,
                     s.total_processed_events,
                     case when s.average_event_processing_time > 0
                          then (1.0 / s.average_event_processing_time)::float8
                     end as capacity_eps
              from subscriptions s
              where #{sets_condition}
              order by s.set, s.name
            SQL
          end
        end
      end
    end
  end
end
