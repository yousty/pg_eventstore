# PgEventstore usage instructions for coding agents

Use these instructions when working in an application that has the `pg_eventstore` gem installed. Follow the
application's existing event, stream, configuration, and subscription conventions before introducing new ones.

## Public API boundary

- Prefer the application-facing entry points `PgEventstore.configure`, `PgEventstore.client`,
  `PgEventstore.maintenance`, and `PgEventstore.subscriptions_manager`.
- Use public value objects such as `PgEventstore::Event`, `PgEventstore::Stream`, `PgEventstore::Subscription`, and
  `PgEventstore::SubscriptionsSet` only for their documented purposes.
- Treat every module or class whose source is marked `# @!visibility private` as an implementation detail. Do not
  instantiate it, reference it from application code, mock it in tests, or depend on its behavior. This includes the
  internal command, query, query-builder, chunk, serializer/deserializer, index, subscription runner/feeder, and web
  implementation layers.
- Do not query or mutate pg_eventstore tables directly. The schema is partitioned and contains derived indexes and
  subscription state that must stay consistent. Use the client, maintenance API, rake tasks, or CLI instead.
- When an unfamiliar constant appears in the gem source, check its YARD visibility and the bundled documentation
  before using it. Being reachable as a Ruby constant does not make it public API.

## Inspect the host application first

Before changing integration code, locate and reuse:

- the existing `PgEventstore.configure` block and named configuration, if any;
- the project's base event class, event naming/versioning convention, payload key convention, and stream factory;
- registered middleware and custom `event_class_resolver` behavior;
- wrappers around `PgEventstore.client`, concurrency/retry policy, and subscription process definitions;
- the dedicated eventstore database and test cleanup setup.

Do not create a second client abstraction or a competing stream naming scheme unless the project explicitly requires
one. Event type names and the `(context, stream_name, stream_id)` tuple are persisted contracts.

## Installation and database setup

PgEventstore requires Ruby 3.3+, PostgreSQL 16+, a separate database, and PostgreSQL's `read committed` default
transaction isolation. A production deployment should normally use a separate PostgreSQL instance and a transaction
pooler such as PgBouncer.

For a new integration, add the setup tasks to the application's `Rakefile`:

```ruby
load 'pg_eventstore/tasks/setup.rake'
```

Then set `PG_EVENTSTORE_URI` and run:

```bash
bundle exec rake pg_eventstore:create
bundle exec rake pg_eventstore:migrate
```

Run migrations when upgrading the gem. `pg_eventstore:drop` deletes the entire eventstore database; never run it
against a non-disposable environment or without explicit authorization.

## Configuration

Configure the gem during application boot and obtain clients through the facade:

```ruby
require 'pg_eventstore'

PgEventstore.configure do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI')
  config.connection_pool_size = 5
  config.connection_pool_timeout = 5
end

client = PgEventstore.client
```

Useful settings include `max_count`, `middlewares`, `event_class_resolver`, connection-pool settings, subscription
retry/timing settings, `eventstore_role`, and `max_events_to_replicate`. Assign settings inside `configure`; do not
mutate the returned frozen config later. Set `PgEventstore.logger` to the host application's logger when appropriate.

Named configurations represent different databases or behavior:

```ruby
PgEventstore.configure(name: :regional_replica) do |config|
  config.pg_uri = ENV.fetch('REGIONAL_EVENTSTORE_URI')
  config.eventstore_role = :replica
end

client = PgEventstore.client(:regional_replica)
manager = PgEventstore.subscriptions_manager(:regional_replica, subscription_set: 'ReadModels')
```

Always pass the intended name consistently. A `:replica` configuration cannot publish events. `:primary` and
`:replica` configurations cannot perform maintenance; only the default `:standalone` role can do both.

Size the connection pool for the process. A normal application process generally needs roughly one connection per
application thread. A subscription process may need up to:

```ruby
number_of_subscriptions + (number_of_subscriptions / 10.0).ceil + 3
```

## Events and streams

Define domain events by subclassing `PgEventstore::Event` unless the project deliberately uses generic events:

```ruby
class UserEmailChanged < PgEventstore::Event
end

event = UserEmailChanged.new(
  data: { 'user_id' => user_id, 'email' => email },
  metadata: { 'actor_id' => actor_id },
  markers: ['user-profile']
)

stream = PgEventstore::Stream.new(
  context: 'Identity',
  stream_name: 'User',
  stream_id: user_id.to_s
)
```

- An event's default `type` is its Ruby class name. Keep persisted event types stable across renames and services. The
  default resolver calls `Object.const_get(type)` and falls back to `PgEventstore::Event`; configure a resolver when
  persisted types do not map directly to constants.
- Event `data` and `metadata` are JSON-backed and are read back with string keys. Prefer JSON-compatible values and the
  key convention already used by the project.
- Event types beginning with `$` are reserved for system events.
- `id` defaults to a UUIDv7, but database-level uniqueness is not guaranteed for application-supplied IDs.
- `global_position`, `stream`, `stream_revision`, link fields, and `created_at` are persistence-assigned. Use the event
  returned by the client when those fields are needed; do not try to set them manually.
- Treat `global_position` as an event identity/pagination coordinate, not a commit timestamp, consistency watermark, or
  cross-stream causal order. `stream_revision` provides ordering within one stream; independent streams can allocate
  global positions and commit in a different order because of PostgreSQL MVCC.
- `PgEventstore::Stream.all_stream` is a read scope over all streams, not a stream to append to.

## Implementing business logic

Organize application behavior around three public-API workflows:

- **Command side:** read the facts needed for a decision, rebuild current state, and validate the command in domain
  code. For a standalone append, use an expected revision that covers every inspected fact. For a cross-stream rule,
  put the minimal read, decision, and appends inside `client.multiple` instead.
- **Query side:** filter and fold events into a query-shaped view. Compute it on demand only when a best-effort live
  result is acceptable. Maintain it with a subscription when the projection must reliably converge after processing
  every matching event.
- **Reactions:** subscribe to events and idempotently update a read model or issue another command. Subscription
  processing is asynchronous and at least once, so do not use it where the originating command requires immediate
  consistency.

Keep decision code separate from storage code. A domain object or pure function should accept events/current state and
return new events or a domain error; the application layer should perform reads, retries, and appends. Do not put mutable
domain state in `PgEventstore::Event` subclasses.

### Choose the consistency boundary deliberately

The consistency mechanism must cover the same set of facts that the business rule inspected:

- Use a **stream revision** when every event in one stream can affect the decision. This is the conventional aggregate
  boundary and makes any concurrent change to that stream invalidate the stale decision.
- Use **Dynamic Consistency Boundaries** when only selected event types, or selected types carrying a marker, affect
  the rule. Unrelated appends to the same stream can then proceed without false conflicts.
- Use `client.multiple` when one invariant spans streams and its filtered read plus authorized writes must be
  immediately consistent, or when several streams in the same configured database must change atomically. It provides
  one serializable transaction across them. Keep the transactional working set small: include every read and write
  involved in the invariant, but no unrelated history or commands. Do not add expected-revision locks inside the
  block; every execution must reread the facts and remake the business decision.
- Use a dedicated coordination/registry stream when a cross-entity invariant needs one authoritative lock boundary.
  For example, email claims can be events in a registry stream and scoped with a stable, opaque claim marker.
- Use subscriptions when eventual consistency is acceptable.

The domain function validates whether the proposed event is allowed. Outside `client.multiple`, expected revisions make
that validation safe by atomically rejecting the append if any covered fact changed after it was read; they do not
replace the business rule. A DCB check applies to the stream receiving the append. Reading the all stream and then
appending to an unrelated stream does not make a cross-stream rule atomic unless both operations execute inside
`client.multiple`. Never choose a boundary narrower than the business rule: an omitted event type or marker cannot
participate in conflict detection.

### Whole-stream aggregate pattern

For an aggregate whose state depends on its complete history, load all pages, fold the events, decide, and append
against the revision that was folded:

```ruby
class MoneyWithdrawn < PgEventstore::Event
end

def account_state(events)
  events.each_with_object({ balance_cents: 0, closed: false }) do |event, state|
    case event.type
    when 'AccountOpened'
      state[:balance_cents] = event.data.fetch('opening_balance_cents')
    when 'MoneyDeposited'
      state[:balance_cents] += event.data.fetch('amount_cents')
    when 'MoneyWithdrawn'
      state[:balance_cents] -= event.data.fetch('amount_cents')
    when 'AccountClosed'
      state[:closed] = true
    end
  end
end

def decide_withdrawal(state, amount_cents)
  raise AccountClosed if state[:closed]
  raise InvalidAmount unless amount_cents.positive?
  raise InsufficientFunds if state[:balance_cents] < amount_cents

  MoneyWithdrawn.new(data: { 'amount_cents' => amount_cents })
end

def load_history(client, stream)
  client.read_paginated(stream, options: { direction: :asc }).flat_map(&:itself)
rescue PgEventstore::StreamNotFoundError
  []
end

def withdraw(client, account_id, amount_cents)
  stream = PgEventstore::Stream.new(
    context: 'Banking',
    stream_name: 'Account',
    stream_id: account_id.to_s
  )
  attempts = 0

  begin
    history = load_history(client, stream)
    state = account_state(history)
    event = decide_withdrawal(state, amount_cents)
    expected_revision = history.empty? ? :no_stream : history.last.stream_revision

    client.append_to_stream(stream, event, options: { expected_revision: })
  rescue PgEventstore::WrongExpectedRevisionError
    attempts += 1
    raise if attempts >= 3

    # Reload, rebuild, and make the decision again; do not merely retry the stale event.
    retry
  end
end
```

Keep reducers and decision functions deterministic: no database calls, current-time reads, random choices, or external
effects. They must produce the same state/decision from the same history. Handle old payload shapes deliberately, and
ignore an event type only when it truly cannot affect the rule.

Do not use a single `read` call to rebuild an unbounded aggregate: it stops at `max_count`. Use `read_paginated`, or use
snapshots implemented by the host application and then replay events after the snapshot revision. A snapshot is a
cache; the event history and expected revision remain authoritative. Start replay at `snapshot_revision + 1`, then
append against the last replayed revision, or against the snapshot revision when no newer event exists.

### Dynamic Consistency Boundary pattern

DCBs reduce unnecessary optimistic-concurrency conflicts in a stream containing several independently changing
subjects. In this example a board is one stream, while each card is identified by a stable marker. Renaming one card
must conflict with creation, rename, or archival of that card, but not with changes to another card:

```ruby
CARD_DECISION_TYPES = %w[CardCreated CardTitleChanged CardArchived].freeze

def rename_card(client, board_id:, card_id:, title:)
  stream = PgEventstore::Stream.new(
    context: 'Planning',
    stream_name: 'Board',
    stream_id: board_id.to_s
  )
  boundary_marker = "card:#{card_id}"
  filters = CARD_DECISION_TYPES.map do |type|
    { type:, markers: [boundary_marker] }
  end

  latest_events = client.read_grouped(
    stream,
    options: { direction: :desc, filter: { event_types: filters } }
  )
  latest_by_type = latest_events.to_h { |event| [event.type, event] }

  raise CardNotFound unless latest_by_type['CardCreated']
  raise CardAlreadyArchived if latest_by_type['CardArchived']

  expected_revision = CARD_DECISION_TYPES.to_h do |type|
    observed = latest_by_type[type]
    revision = observed ? observed.stream_revision : :no_event
    [type, { expected_revision: revision, markers: [boundary_marker] }]
  end

  event = CardTitleChanged.new(
    data: { 'card_id' => card_id, 'title' => title },
    markers: [boundary_marker]
  )
  client.append_to_stream(stream, event, options: { expected_revision: })
rescue PgEventstore::StreamNotFoundError
  raise CardNotFound
end
```

If two processes rename the same card from the same observed state, one append succeeds and the other raises
`PgEventstore::WrongExpectedTypesRevisionError`. A change carrying another card's marker does not conflict. Catch that
error at the application boundary and repeat the entire read/validate/append operation with a retry limit.

Use `read_grouped(direction: :desc)` only when the latest event of each relevant type is sufficient to decide. If the
rule depends on every occurrence, use a filtered `read_paginated` fold and take the most recent observed revision for
each type/marker boundary. Put the same stable boundary marker on every event that participates in the rule. Markers
are persisted and indexed, so keep them non-secret and purposeful; marker lists use OR semantics.

### Cross-stream consistency with `client.multiple`

When one business invariant genuinely spans streams, `client.multiple` is the powerful consistency mechanism to use.
It makes the minimal fact read, decision, and one or more necessary appends part of one serializable operation;
per-stream expected revisions and DCBs cannot by themselves protect facts held in other streams. A bare all-stream
projection followed by a separate append cannot protect such an invariant.

Keep the serializable unit small without weakening the invariant. "Small" describes the events read and changed for
one decision, not the number of streams across which the invariant may range. For example, users have separate
streams, but a username must be unique across all of them. The query below is deliberately narrow: one context/name,
one event type, one indexed marker, and at most one row:

```ruby
class UsernameClaimed < PgEventstore::Event
end

def claim_username(client, user_id:, username:, username_key:)
  user_stream = PgEventstore::Stream.new(
    context: 'Identity',
    stream_name: 'User',
    stream_id: user_id.to_s
  )
  marker = "username:#{username_key}" # A stable, non-secret/opaque lookup key.

  client.multiple do
    existing_claim = client.read(
      PgEventstore::Stream.all_stream,
      options: {
        max_count: 1,
        filter: {
          streams: [{ context: 'Identity', stream_name: 'User' }],
          event_types: [{ type: 'UsernameClaimed', markers: [marker] }]
        }
      }
    ).first
    raise UsernameTaken if existing_claim

    event = UsernameClaimed.new(
      data: { 'user_id' => user_id, 'username' => username },
      markers: [marker]
    )
    client.append_to_stream(user_stream, event)
  end
end
```

`client.multiple` uses PostgreSQL `SERIALIZABLE` isolation. The read and append therefore have an outcome equivalent to
some serial execution. If concurrent username claims create a serialization conflict, PostgreSQL aborts one transaction
and pg_eventstore reruns its entire block; the retried block then observes the winning claim and raises `UsernameTaken`.

This is the event-store form of `SELECT` followed conditionally by `INSERT`: read the exact fact, return or raise when it
already exists, and append only when it does not. Both steps must happen inside the block on every execution. Do not
load state, construct a supposedly final event, or capture a revision before entering `multiple`, because a retry must
base the business decision on its own fresh reads.

Do not pass `expected_revision` to an append inside `multiple`. It adds no protection for facts read by the same
serializable block. When concurrency invalidates those reads, the transaction conflict causes pg_eventstore to rerun
the whole block; its control flow must then reach the correct result from the events it now reads. A caller-supplied
revision check is not a substitute for that retriable business logic and can turn a valid rerun into a revision error.

The precise guarantee is serial equivalence, not that every concurrent append literally causes a retry. PostgreSQL may
validly order the block before a concurrent transaction. The published event is consistent with that serial order, but
is not necessarily based on every transaction that physically commits while the block is running.

Serializable transactions are resource-intensive. Keep this pattern selective, bounded, and short: use exact stream,
event-type, and marker filters, read only the facts required by the invariant, and mutate only the necessary streams.
Appending to more than one stream is appropriate when those writes must be atomic for the same invariant; unrelated
events and commands belong outside the block.

Do not put an unbounded `read_paginated` replay, dashboard/report projection, broad all-stream fold, or large set of
partitions/streams inside `multiple`. Model a narrower registry/coordination stream or marker boundary when possible;
use a subscription when a broad projection can be eventually consistent.

If a genuinely bounded paginated read is unavoidable, fully consume its lazy enumerator inside the `multiple` block;
consuming it afterward performs the reads outside the transaction. The block can rerun, so keep its
projection/decision deterministic and move HTTP calls, emails, jobs, and other external effects outside. This pattern
makes a small synchronous decision consistent; it does not create a durable projection position like a subscription
does.

## Appending and concurrency

Use `append_to_stream`; it returns the persisted event, or an array of persisted events:

```ruby
persisted_event = client.append_to_stream(
  stream,
  event,
  options: { expected_revision: :no_stream }
)
```

Passing an array appends all events atomically and in order. Use optimistic concurrency for business writes:

- `:any` performs no check and is the default;
- `:no_stream` requires the stream not to exist;
- `:stream_exists` requires it to exist;
- an integer requires the current stream revision to equal that value.

`client.stream_revision(stream)` is the efficient revision lookup and returns
`PgEventstore::Stream::NON_EXISTING_STREAM_REVISION` (`-1`) for a missing stream. When state was built by reading a
stream, normally use the last event's `stream_revision` for the subsequent append.

Handle `PgEventstore::WrongExpectedRevisionError` by re-reading the stream, rebuilding state, rechecking business
rules, and then making a bounded retry. Do not blindly retry the same stale write. Per-event-type Dynamic Consistency
Boundaries are available by passing a type-to-revision map and raise
`PgEventstore::WrongExpectedTypesRevisionError` on mismatch:

```ruby
client.append_to_stream(
  stream,
  event,
  options: {
    expected_revision: {
      'UserCreated' => :event_exists,
      'UserEmailChanged' => { expected_revision: 3, markers: ['verified'] }
    }
  }
)
```

Per-type revision values are `:any`, `:no_event`, `:event_exists`, or an integer. Marker lists have OR semantics, not
AND semantics; introduce a combined marker when an AND-like distinction is required.

Expected-revision locks belong to the standalone read/decide/append workflow. Omit them inside `client.multiple`; let
the serializable transaction retry the complete in-block read and decision instead.

Use `client.multiple` when commands against the same configured eventstore must share one PostgreSQL `SERIALIZABLE`
transaction:

```ruby
client.multiple do
  client.append_to_stream(first_stream, first_event)
  client.append_to_stream(second_stream, second_event)
end
```

Keep the block small. It may be executed more than once because of concurrent schema/index creation or transaction
retries. Put emails, jobs, HTTP calls, and other non-idempotent side effects outside the block. Use
`multiple(read_only: true)` only for read-only commands; writes then raise `PG::ReadOnlySqlTransaction`.

## Reading

Read a specific stream or the all-stream scope through the client:

```ruby
events = client.read(
  stream,
  options: {
    direction: :asc,
    from_revision: 0,
    max_count: 100,
    filter: { event_types: ['UserEmailChanged'] }
  }
)
```

- A missing specific stream raises `PgEventstore::StreamNotFoundError`; decide explicitly whether that means empty
  state or an application error.
- Use `from_revision`/`to_revision` for a specific stream and `from_position`/`to_position` for
  `PgEventstore::Stream.all_stream`.
- `direction` accepts `:asc`/`:desc` as well as the documented string forms.
- `resolve_link_tos: true` returns original events when reading a projection stream containing links.
- Filters use `event_types`, whose entries may be type strings or hashes such as
  `{ type: 'UserEmailChanged', markers: ['verified'] }`. On the all stream, `streams` entries must contain `context`,
  `context` plus `stream_name`, or all three stream attributes. Do not rely on invalid partial filters being rejected;
  some are ignored.
- Marker alternatives are ORed. On all-stream reads, a marker-only filter combined with only `context`, or with
  `context` and `stream_name`, must also specify an event type.

Use `read_paginated` for unbounded histories. It returns an enumerator that yields arrays, not individual events:

```ruby
client.read_paginated(PgEventstore::Stream.all_stream, options: { max_count: 500 }).each do |batch|
  batch.each { |event| project(event) }
end
```

Use `read_grouped` when the requirement is one oldest or newest event per event type. Its `max_count` option is ignored.
On the all stream, equal event types are distinguished by their `context`/`stream_name` pair, not by `stream_id`; do
not use it to fetch one latest event per entity across otherwise identical entity streams. Use `read_streams` and
`read_streams_paginated` to enumerate streams; paginated stream reads also yield arrays.

## Building projections and query models

A projection function can be a deterministic fold from selected events to query-shaped state, but that does not make
every way of supplying its input reliable or idempotent. Keep the fold pure enough to replay, handle every historical
event version that can be returned, and test it in per-stream revision order with plausible cross-stream interleavings.
Select the implementation based on the required guarantees:

- Build an **on-demand projection** with `read`/`read_paginated` when the filtered history is bounded, the query is
  infrequent, and a potentially incomplete best-effort result during concurrent writes is acceptable. The Read API has
  no durable projection position and does not guarantee a gap-free all-stream scan.
- Use `read_grouped` when the projection needs only the oldest or newest event of each type, not accumulated history.
- Maintain a **link stream** when several consumers need the same ordered subset of existing events without copying
  their payloads.
- Maintain an external **materialized view** with a subscription when queries are frequent, histories are large, or
  the view must reliably converge by eventually processing every matching event.

This differs from command-side validation. Outside `client.multiple`, a command read is followed by an
expected-revision check that atomically rejects a decision based on stale covered facts. Inside `multiple`, the minimal
filtered read, decision, and writes are protected by serializable transaction retries instead. A standalone on-demand
query fold has neither validation mechanism. Do not use an all-stream on-demand projection as the authority for
invariants, exact financial totals, uniqueness, or other decisions that require a complete event set.

### On-demand (on-the-fly) filtered projection

The all-stream read API can combine stream scope, event types, markers, and direction. For example, events in every
order stream can carry a `customer:<id>` marker, allowing a customer summary to be computed without loading unrelated
orders:

```ruby
ORDER_OVERVIEW_TYPES = %w[OrderPlaced OrderCancelled OrderShipped].freeze

def customer_order_overview(client, customer_id)
  customer_marker = "customer:#{customer_id}"
  options = {
    direction: :asc,
    max_count: 500,
    filter: {
      streams: [{ context: 'Sales', stream_name: 'Order' }],
      event_types: ORDER_OVERVIEW_TYPES.map do |type|
        { type:, markers: [customer_marker] }
      end
    }
  }
  overview = { orders: {} }
  client.read_paginated(PgEventstore::Stream.all_stream, options:).each do |batch|
    batch.each do |event|
      order_id = event.data.fetch('order_id')

      case event.type
      when 'OrderPlaced'
        overview[:orders][order_id] = {
          status: :placed,
          total_cents: event.data.fetch('total_cents')
        }
      when 'OrderCancelled'
        order = (overview[:orders][order_id] ||= { total_cents: nil })
        order[:status] = :cancelled
      when 'OrderShipped'
        order = (overview[:orders][order_id] ||= { total_cents: nil })
        order[:status] = :shipped
      end
    end
  end
  overview
end
```

The overview tolerates a status event whose earlier placement event was absent from this live pass, leaving
`total_cents` unknown. That is appropriate only because the result is explicitly non-authoritative and can be rebuilt.

This example repeats the marker constraint for each event type because an all-stream marker-only filter combined with
`context` and `stream_name` is not supported. Stream filters and event-type filters form unions of their matching
combinations; design the filter and test it against events that must both match and not match.

Use `read_paginated` directly, but treat the result as a best-effort live view. Its pages are not one MVCC snapshot and
the Read API stores no durable progress for the projection. An independent transaction can allocate a smaller
`global_position`, remain uncommitted while a higher position becomes visible, and commit after the pagination cursor
has advanced. That event may be absent from the current pass and appear only when the projection is rebuilt later.
Re-running the fold after writers settle can produce a complete result, but one live execution has no such guarantee.

Adding `to_position` does not fix this: it restricts numeric positions but does not create a commit-order watermark or
a stable point-in-time view. Use `from_position`/`to_position` only when the requirement is explicitly about a known
numeric position range. Do not infer causality or business order between different streams from `global_position`;
make a cross-stream fold insensitive to interleaving, or encode the required relationship in domain events, links, or
causation metadata. For a durable projection that must eventually process every matching event, use a subscription and
an idempotent handler.

### Materialized projection

When a projection must reliably converge, define a subscription with the same filters and update a query database in
the handler. Subscriptions use deterministic subscription positions and persist progress separately from
`global_position`, allowing a healthy/recoverable subscription to process every matching event eventually while
preserving revision order within a stream. Delivery is still at least once: make the update idempotent using a source
identity such as the source config plus `event.global_position`, or the event's stream tuple plus `stream_revision`.
Advance application-visible state in the same database transaction as that idempotency record where possible. A failed
handler or batch can run again.

Treat the materialized view as rebuildable derived data. Keep its projection function usable by both the live
subscription and a replay task, and store enough schema/version information to evolve old event payloads. If immediate
read-after-write behavior is required for one known stream, read that stream directly. Do not expect either an
all-stream on-demand fold or a materialized view to provide an immediate cross-stream snapshot.

## Linking events

Use links for projection streams. Only persisted events can be linked:

```ruby
persisted = client.append_to_stream(source_stream, event)
client.link_to(projection_stream, persisted, options: { expected_revision: :no_stream })

projected_events = client.read(projection_stream, options: { resolve_link_tos: true })
```

`link_to` accepts one event or an array and supports the same stream-level concurrency options as appending. Unlike
normal append/read operations, link events use no configured middleware by default; pass middleware keys explicitly if
needed. Deleting an original event or stream does not automatically delete links to it.

## Subscriptions

Create subscriptions through a manager and give the set and each subscription a stable, application-specific name:

```ruby
manager = PgEventstore.subscriptions_manager(subscription_set: 'IdentityReadModels')
manager.subscribe(
  'ProjectUsers',
  handler: ->(event) { UserProjector.call(event) },
  options: {
    filter: {
      streams: [{ context: 'Identity', stream_name: 'User' }],
      event_types: %w[UserCreated UserEmailChanged]
    }
  }
)
manager.start
```

For a dedicated process, put configuration and definitions in a Ruby file and start it with:

```bash
pg-eventstore subscriptions start -r ./subscriptions.rb
```

- Subscription names must be unique within a set. Treat set/name pairs as persistent identities because positions and
  locks are stored under them.
- Run a given subscription set in only one manager/process. Do not use `force_lock: true` as routine failover; it can
  cause duplicate processing and broken positions. Use `start!` when lock failure must raise; `start` logs the lock
  error and returns `nil`.
- Treat delivery as at least once. Handlers must be idempotent. If `in_batches: true` is used, the handler receives an
  array and a failed batch is delivered again in full.
- Subscription `options[:from_position]` is an exclusive subscription position, not
  `Event#global_position`. Subscription ordering can differ from global-position ordering, although revision order is
  preserved within one stream.
- Subscription filters follow all-stream filter syntax, but additionally allow marker-only filters with partial stream
  scopes and type-prefix entries such as `{ prefix: 'User' }`.
- Per-subscription retry, interval, notifier, shutdown, middleware, and batching options may override configuration.
  Keep CPU-heavy subscriptions limited per process and size the connection pool accordingly.

## Middleware and event tracing

Middleware mutates events before persistence and after reads/subscription delivery. Include `PgEventstore::Middleware`
or provide an object responding to both `serialize(event)` and `deserialize(event)`, then register named instances:

```ruby
class RedactSecrets
  include PgEventstore::Middleware

  def serialize(event)
    # Mutate the event in place.
  end

  def deserialize(event)
    # Restore or transform the event in place.
  end
end

PgEventstore.configure do |config|
  config.middlewares = { redact_secrets: RedactSecrets.new }
end
```

Commands can retry, so both methods must be deterministic and retry-safe, and any external effects must be idempotent.
Append, read, and subscription calls use all configured middleware by default; passing `middlewares: [:name]` selects
only those entries. Links are the exception and default to none.

`#deserialize` also runs on the event(s) returned by `append_to_stream`/`link_to`. A middleware whose `#deserialize` is
expensive and irrelevant on the write path can opt out of that by implementing `deserialize_on_append?` and returning
`false`; reads and subscriptions keep calling it. Do not opt out middlewares whose attributes are read from the
returned event, such as `PgEventstore::Middleware::EventTracing`.

To opt into causation/correlation tracing, register `PgEventstore::Middleware::EventTracing` and pass a persisted event
as `caused_by:` when creating the next event. The middleware then assigns `causation_id`, propagates or creates
`correlation_id`, and indexes the identifiers as feature markers.

## Maintenance, replication, and tests

- Use `PgEventstore.maintenance.delete_stream(stream)` or `delete_event(event)` only for explicit maintenance needs,
  not ordinary domain behavior. Both return `false` when the target is missing. Deleting an early event renumbers later
  revisions and can lock many rows; `force: true` bypasses the safety limit and must be used deliberately. Any delete
  operation may require further, deeper maintenance actions, such as reindexing related indexes, thus avoid maintenance
  API at all cost. Do not use it in any business logic.
- Configure replication through named `:primary` and `:replica` configs and the public
  `manager.create_replication` API. Do not attempt to copy selected internal tables manually.
- For RSpec integration tests, require `pg_eventstore/rspec/test_helpers` and call
  `PgEventstore::TestHelpers.clean_up_db` (or pass a named test config). This helper is destructive: point it only at a
  dedicated test database, and do not run concurrent examples that clean the same database.
- Test through the public facade. Cover optimistic-concurrency conflicts, missing streams, event round trips,
  middleware retry safety, and subscription-handler idempotency when those behaviors matter.

For edge cases and complete option lists, consult the gem's bundled chapters on
- [configuration](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/configuration.md)
- [events and streams](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/events_and_streams.md)
- [appending](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/appending_events.md)
- [reading](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/reading_events.md)
- [linking](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/linking_events.md)
- [subscriptions](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/subscriptions.md)
- [middleware](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/writing_middleware.md)
- [maintenance](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/maintenance.md)
- [multiple commands](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/multiple_commands.md)
- [replication](https://raw.githubusercontent.com/yousty/pg_eventstore/refs/heads/main/docs/replication.md)
