# Prometheus metrics

`pg_eventstore` ships rack endpoints which expose subscriptions observability data in the
[Prometheus text exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/). They answer the
questions the [Admin UI](admin_ui.md) subscriptions page answers, but in a form Prometheus can scrape and Grafana can
graph and alert on.

## Endpoints

Metrics are split per path so that each scrape runs only the query it needs, and cheap families can be polled at a
different interval than the expensive one:

| Path | Metrics | Query cost |
|---|---|---|
| `/subscriptions/latency` | lag of every alive subscription + store positions | the only one touching the `events` table (one index hop per subscription) |
| `/subscriptions/health` | state, lock, heartbeat age, restarts, last error age | single read of the `subscriptions` table |
| `/subscriptions/throughput` | processed events counter, handler capacity | single read of the `subscriptions` table |
| `/` | all of the above | all of the above |

The root path is meant for humans and ad-hoc checks; point your scrape jobs at the split paths.

Every query is guarded by a `statement_timeout` of 5 seconds - a stuck scrape fails visibly instead of piling up on
the database.

### Which subscriptions are reported

The `subscriptions` table is a registry which never garbage-collects: every handler that was ever registered keeps its
row, including handlers that were later renamed or removed. To keep dashboards meaningful, the endpoints only report
subscriptions which are either locked by a subscriptions set or were updated within the last 10 minutes. A
subscription that died *without releasing its lock* is deliberately still reported - detecting it is what
`pg_eventstore_subscription_heartbeat_age_seconds` is for.

## Mounting

### Alongside the Admin UI

The Admin UI application serves the same metrics under `/metrics`:

```
/metrics
/metrics/subscriptions/latency
/metrics/subscriptions/health
/metrics/subscriptions/throughput
```

Whatever authentication protects your Admin UI protects these paths too. This is convenient for eyeballing raw values
in the browser, but usually inconvenient for Prometheus - scrapers can not pass human-oriented authentication.

### Standalone application

`PgEventstore::Web::Metrics::Application` is a separate rack application designed to be a scrape target. In your
`config/routes.rb`:

```ruby
require 'pg_eventstore/web'

mount PgEventstore::Web::Metrics::Application, at: '/pg_eventstore/metrics'
```

Or as a standalone `config.ru`:

```ruby
require 'pg_eventstore/web'

run PgEventstore::Web::Metrics::Application
```

It supports static bearer token authentication out of the box: set the `PG_EVENTSTORE_METRICS_TOKEN` environment
variable and every request must carry an `Authorization: Bearer <token>` header. When the variable is not set the
application is open, and protecting it is your responsibility.

It uses the `:metrics` config when defined, with a fallback to the default config. This lets you point metrics at a
replica or restrict its pool size:

```ruby
PgEventstore.configure(name: :metrics) do |config|
  config.pg_uri = ENV['PG_EVENTSTORE_URI']
  config.connection_pool_size = 1
end
```

## Prometheus scrape config

```yaml
scrape_configs:
  - job_name: 'pg-eventstore-subscriptions-latency'
    metrics_path: /pg_eventstore/metrics/subscriptions/latency
    scrape_interval: 30s
    authorization:
      type: Bearer
      credentials: <token>
    static_configs:
      - targets: ['your-app-host:port']
  - job_name: 'pg-eventstore-subscriptions-health'
    metrics_path: /pg_eventstore/metrics/subscriptions/health
    scrape_interval: 30s
    authorization:
      type: Bearer
      credentials: <token>
    static_configs:
      - targets: ['your-app-host:port']
  - job_name: 'pg-eventstore-subscriptions-throughput'
    metrics_path: /pg_eventstore/metrics/subscriptions/throughput
    scrape_interval: 60s
    authorization:
      type: Bearer
      credentials: <token>
    static_configs:
      - targets: ['your-app-host:port']
```

The split into three jobs is intentional - do not collapse them into a single `/` scrape unless you are fine with
every scrape paying the latency query.

## Metrics reference

All per-subscription metrics carry `set` and `name` labels.

### Latency

`pg_eventstore_subscription_lag_events` (gauge)

Number of events between the subscription's checkpoint and the subscription positions frontier.

Note on units: `Subscription#current_position` is a checkpoint in *subscription position* units - the dense,
commit-ordered sequence assigned via the `event_subscription_positions` table - not in `events.global_position` units.
The global position sequence contains gaps and runs ahead, so comparing a checkpoint against it wildly over-reports
lag. This metric compares against the frontier of assigned subscription positions, which is the correct reference.

`pg_eventstore_subscription_lag_seconds` (gauge)

Age of the oldest event the subscription has not processed yet. `0` when fully caught up. Because
`event_subscription_positions` rows are pruned over time, for a subscription that is very far behind this reports the
age of the oldest *retained* unprocessed event - a lower bound. When `lag_seconds` and `lag_events` disagree, trust
`lag_events`.

`pg_eventstore_store_frontier_position` (gauge)

Latest assigned subscription position. The frontier only advances while at least one subscriptions process runs its
events position worker; when every subscriptions process is down, lag freezes - that situation is caught by the
heartbeat metric below, not by the lag metrics.

`pg_eventstore_store_head_global_position` (gauge)

Latest value of the events global position sequence. Contains gaps; do not compare subscription checkpoints against
it.

### Health

`pg_eventstore_subscription_state` (gauge, extra `state` label, value is always 1)

Last *recorded* state. A subscription killed without a graceful shutdown keeps `state="running"` and its lock
forever - correlate with the heartbeat age below.

`pg_eventstore_subscription_locked` (gauge, 0/1)

Whether the subscription is currently locked by a subscriptions set.

`pg_eventstore_subscription_heartbeat_age_seconds` (gauge)

Seconds since the subscription row was last touched by its runner. Alive subscriptions update it about every 10
seconds. **A locked subscription with a stale heartbeat is a dead process** - this is the signal to alert on for
process death, since neither `state` nor the lock can be trusted for that.

`pg_eventstore_subscription_restarts_total` (counter)

Times the subscription was restarted after a failure.

`pg_eventstore_subscription_last_error_age_seconds` (gauge)

Seconds since the last error. Absent when the subscription never failed.

### Throughput

`pg_eventstore_subscription_processed_events_total` (counter)

Total number of events processed. Use `rate()` over it for the actual current throughput - it correctly drops to 0
when no matching events arrive.

`pg_eventstore_subscription_capacity_events_per_second` (gauge)

Derived from the average handler execution time of the last few processed events, *whenever they happened*. It
answers "how fast can this handler go when it is fed" and is sticky while the subscription is idle - do not read it
as current throughput. The ratio `rate(processed_events_total) / capacity` is a useful saturation signal: a
subscription running close to its capacity has no headroom left, and a traffic spike will turn directly into lag.

## Alerting suggestions

- Lagging read models: `pg_eventstore_subscription_lag_seconds > 300 for 10m`
- Dead subscription process: `pg_eventstore_subscription_locked == 1 and pg_eventstore_subscription_heartbeat_age_seconds > 60 for 10m`
- No headroom: `rate(pg_eventstore_subscription_processed_events_total[5m]) / pg_eventstore_subscription_capacity_events_per_second > 0.8 for 15m`

## Database permissions

For a dedicated read-only role, the endpoints need `SELECT` on `subscriptions`, `events`,
`event_subscription_positions` and both sequences (`events_global_position_seq`,
`event_subscription_positions_subscription_position_seq`).
