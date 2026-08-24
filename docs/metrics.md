# Prometheus metrics

`pg_eventstore` ships rack endpoints which expose subscriptions observability data in the
[Prometheus text exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/). They answer the
questions the [Admin UI](admin_ui.md) subscriptions page answers, but in a form Prometheus can scrape and Grafana can
graph and alert on.

## Endpoints

Metrics are grouped into domains, and split per path within a domain so that each scrape runs only the query it
needs and cheap families can be polled at a different interval than the expensive one. Paths below are relative to
wherever the app is mounted - mounted at `/pg_eventstore/metrics` the first one is
`/pg_eventstore/metrics/subscriptions/latency`.

| Path | Metrics | Query cost |
|---|---|---|
| `/subscriptions/latency` | lag of every reported subscription + store positions | the only one looking at event positions (one index range scan per subscription) |
| `/subscriptions/health` | state, lock, heartbeat age, restarts, last error age | single read of the `subscriptions` table |
| `/subscriptions/throughput` | processed events counter, handler capacity | single read of the `subscriptions` table |
| `/subscriptions` | all of the above | all of the above |

The domain path (`/subscriptions`) is meant for humans and ad-hoc checks; point your scrape jobs at the split paths.

**There is deliberately no route serving every domain at once.** `/metrics` is the Prometheus convention, so a route
there would invite pointing scrape jobs at it by reflex - and every such scrape would pay for every query, including
the expensive ones, which is exactly what the per-path split exists to avoid. Keeping aggregates per domain also
keeps each response bounded as more domains are added.

Every query is guarded by a `statement_timeout` of 5 seconds - a stuck scrape fails visibly instead of piling up on
the database.

### Which subscriptions are reported

Every subscription in the queried database, unless you narrow it down with `set` params (see
[Reporting only some subscription sets](#reporting-only-some-subscription-sets)). Note that the subscriptions registry
never removes rows, so handlers that were renamed or removed keep theirs and are reported too.

A subscription that died *without releasing its lock* is reported like any other - detecting it is what
`pg_eventstore_subscription_heartbeat_age_seconds` is for, and it is the most useful thing to alert on: neither the
state column nor the lock can be trusted to notice a process that went away.

## Mounting

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

### Authorization

The application ships without authentication - how you protect the endpoint is up to you, exactly as it is for the
[Admin UI](admin_ui.md#authorization). Wrap it in whatever middleware your setup already uses, for example:

```ruby
metrics_app = Rack::Builder.new do
  use Rack::Auth::Basic do |_username, password|
    Rack::Utils.secure_compare(ENV.fetch('PG_EVENTSTORE_METRICS_PASSWORD'), password)
  end
  run PgEventstore::Web::Metrics::Application
end

mount metrics_app, at: '/pg_eventstore/metrics'
```

### Choosing the database

Which store is queried is decided per request by the `config` query param, so one mounted application can serve the
metrics of every configured database:

```ruby
PgEventstore.configure(name: :db1) do |config|
  config.pg_uri = ENV['DB1_URI']
  config.connection_pool_size = 1
end

PgEventstore.configure(name: :db2) do |config|
  config.pg_uri = ENV['DB2_URI']
  config.connection_pool_size = 1
end
```

```
GET /pg_eventstore/metrics/subscriptions/latency?config=db1
```

An unknown or missing `config` falls back to the default configuration.

### Reporting only some subscription sets

Rows of the subscriptions registry are never removed, so a database that has been running for a while also holds
handlers that were renamed, removed, or never ran against it. Pass one or more `set` params to report only the
subscriptions you care about:

```
GET /pg_eventstore/metrics/subscriptions/health?set=MyAppSet&set=MyOtherSet
```

Without a `set` param every subscription in the database is reported. Since a subscription set is usually named after
the application that owns it, scoping the scrape by set is the straightforward way to keep one application's
dashboards to its own subscriptions.

## Prometheus scrape config

```yaml
scrape_configs:
  - job_name: 'pg-eventstore-subscriptions-latency'
    metrics_path: /pg_eventstore/metrics/subscriptions/latency
    scrape_interval: 30s
    params:
      config: ['db1']
      set: ['MyAppSet']
    static_configs:
      - targets: ['your-app-host:port']
  - job_name: 'pg-eventstore-subscriptions-health'
    metrics_path: /pg_eventstore/metrics/subscriptions/health
    scrape_interval: 30s
    params:
      config: ['db1']
      set: ['MyAppSet']
    static_configs:
      - targets: ['your-app-host:port']
  - job_name: 'pg-eventstore-subscriptions-throughput'
    metrics_path: /pg_eventstore/metrics/subscriptions/throughput
    scrape_interval: 60s
    params:
      config: ['db1']
      set: ['MyAppSet']
    static_configs:
      - targets: ['your-app-host:port']
```

Add whatever credentials your chosen protection needs to these jobs - Prometheus supports `basic_auth`,
`authorization` and `tls_config` per job.

The split into three jobs is intentional - do not collapse them into a single `/subscriptions` scrape unless you
are fine with every scrape paying the latency query.

## Metrics reference

All per-subscription metrics carry `set` and `name` labels.

### Latency

`pg_eventstore_subscription_lag_events` (gauge)

How many events the subscription still has to catch up on before it reaches the edge of the `"all"` stream and starts
processing newly appended events.

Note on filters: a subscription's filter is accounted for by the store, so a caught-up subscription reports `0` no
matter how narrow its filter is - traffic it does not care about never shows up as its lag. For a *lagging*
subscription the value counts everything in the range it has not reached yet, matching its filter or not. Read it as
staleness ("how far behind is this subscription"), not as the number of events its handler is about to run: that
number is usually much smaller, because non-matching ranges are skipped without invoking the handler.

`pg_eventstore_subscription_lag_seconds` (gauge)

Age of the oldest event the subscription has not processed yet. `0` when fully caught up.

The metric is absent for a subscription whose oldest unprocessed event no longer exists, which happens when that
event or its stream was deleted. Reporting `0` there would read as "caught up", so nothing is reported instead and
`lag_events` remains the source of truth for the backlog.

`pg_eventstore_store_frontier_position` (gauge)

Latest position assigned to an event, which is what subscription checkpoints are measured against. It only advances
while at least one subscriptions process is running; when they are all down, lag stops growing - that situation shows
up in the heartbeat metric below, not in the lag metrics.

`pg_eventstore_store_head_global_position` (gauge)

Global position of the newest event in the store. Contains gaps; do not compare subscription checkpoints against it.

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
