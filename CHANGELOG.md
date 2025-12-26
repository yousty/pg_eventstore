## [Unreleased]

- **Breaking change**: `pg_eventstore` now requires [nextval_with_xact_lock](https://github.com/intale/nextval_with_xact_lock/) extension
- **Breaking change**: `pg_eventstore` now requires PostgreSQL v16+
- Greatly decreased the number of connections, used by `pg_eventstore` subscriptions

## [1.13.4]

- Fix subscriptions potentially skipping events when multiple events are appended in concurrent transactions

## [1.13.3]

- Reduce subscription delays for newly published events

## [1.13.2]

- Fix a bug that prevents correct processing of CLI commands using public API

## [1.13.1]

- Do not modify public methods arguments

## [1.13.0]

- Introduce automatic subscriptions recovery from connection errors. This way if a subscription process loses the connection to the database - it will be trying to reconnect until the connection is restored.
- Resolve ambiguity in usage of `PgEventstore.config` method. It now returns the frozen object.

## [1.12.0]

- Introduce `#read_grouped` API method that allows to group events by type

## [1.11.0]

- Add a global position that caused an error to the subscription's error JSON info. This will help you understand what event caused your subscription to fail.
- Improve long payloads in JSON preview in admin web UI in the way it does not moves content out of the visible area.
- Admin UI: adjust events filtering and displaying of stream context, stream name, stream id and event type when values of them contain empty strings or non-displayable characters

## [1.10.0]
- Admin UI: Adjust `SubscriptionSet` "Stop"/"Delete" buttons appearance. Now if `SubscriptionsSet` is not alive anymore(the related process is dead or does not exist anymore) - "Delete" button is shown. If `SubscriptionSet` is alive - "Stop" button is shown
- Admin IU: fixed several potential XSS vulnerabilities
- Admin IU: Add "Copy to clipboard" button near stream id that copies ruby stream definition
- Admin UI: allow deletion of streams with empty attribute values

## [1.9.0]

- Implement an ability to delete a stream
- Implement an ability to delete an event
- Add "Delete event" and "Delete stream" buttons into admin UI

## [1.8.0]
- Introduce default config for admin web UI. Now if you define `:admin_web_ui` config - it will be preferred over default config
- Fix pagination of events in admin UI
- Improve partial index for `$streams` system stream

## [1.7.0]
- Implement reading from `"$streams"` system stream
- Disable Host authorization introduced in sinatra v4.1

## [1.6.0]
- Introduce subscriptions CLI. Type `pg-eventstore subscriptions --help` to see available commands. The main purpose of it is to provide the single way to start/stop subscription processes. Check [Subscriptions](docs/subscriptions.md#creating-a-subscription) docs about the new way to start and keep running a subscriptions process.

## [1.5.0]
- Add ability to toggle link events in the admin UI
- Mark linked events in the admin UI with "link" icon

## [1.4.0]
- Add an ability to configure subscription graceful shutdown timeout globally and per subscription. Default value is 15 seconds. Previously it was hardcoded to 5 seconds. Examples:

```ruby
# Set it globally, for all subscriptions
PgEventstore.configure do |config|
  config.subscription_graceful_shutdown_timeout = 5
end

# Set it per subscription
subscriptions_manager.subscribe(
  'MySubscriptionWithHeavyLiftingTask',
  handler: proc { |event| puts event },
  graceful_shutdown_timeout: 20
)
```

## [1.3.4]
- Fix `NoMethodError` error in `Client#read_paginated` when stream does not exist or when there are no events matching the given filter

## [1.3.3]
- Adjust default value of `subscription_max_retries` setting

## [1.3.2]
- Fix UI when switching subscription status

## [1.3.1]
- Swap "Search" button and "Add filter" button on Dashboard page

## [1.3.0]
- Add ability to filter subscriptions by state in admin UI
- Reset error-related subscription's attributes on subscription restore
- Reset total processed events number when user changes subscription's position
- Allow to search event type, stream context and stream name by substring in web UI
- Relax sinatra version requirement to v3+

## [1.2.0]
- Implement `failed_subscription_notifier` subscription hook.

Now you are able to define a function that is called when subscription fails and no longer can be automatically restarted because it hit max number of retries. You can define the hook globally in the config and per subscription. Examples:

```ruby
PgEventstore.configure do |config|
  config.failed_subscription_notifier = proc { |sub, error| puts "Subscription: #{sub.inspect}, error: #{error.inspect}" }
end

subscriptions_manager = PgEventstore.subscriptions_manager(subscription_set: 'MyApp')
# Overrides config.failed_subscription_notifier function
subscriptions_manager.subscribe(
  'My Subscription 1',
  handler: Handler.new('My Subscription 1'),
  options: { filter: { event_types: ['Foo'] } },
  failed_subscription_notifier: proc { |_subscription, err| p err }
)
# Uses config.failed_subscription_notifier function
subscriptions_manager.subscribe(
  'My Subscription 2',
  handler: Handler.new('My Subscription 2'),
  options: { filter: { event_types: ['Bar'] } }
)
```

## [1.1.5]
- Review the way to handle SubscriptionAlreadyLockedError error. This removes noise when attempting to lock an already locked subscription.

## [1.1.4]
- Add rbs signatures

## [1.1.3]
- Fix issue with assets caching between different gem's versions

## [1.1.2]
- Improve web app compatibility with rails

## [1.1.1]
- Allow case insensitive search by context, stream name and event type in admin UI

## [1.1.0]
- Add "Reset position" button on Subscriptions Admin UI page

**Note** This release includes a migration to support new functional. Please don't forget to run `rake pg_eventstore:migrate` to apply latest db changes.

## [1.0.4]
- Fix bug which caused slow Subscriptions to stop processing new events
- Optimize Subscriptions update queries

## [1.0.3]
- Do no update `Subscription#last_chunk_fed_at` if the chunk is empty

## [1.0.2]
- UI: Fix opening of SubscriptionsSet tab of non-existing SubscriptionsSet

## [1.0.1]
- Adjust assets urls to correctly act when mounting sinatra app under non-root url

## [1.0.0]

- Improve performance of Subscription#update by relaxing transaction isolation level
- Fix calculation of events number in the subscription's chunk

## [1.0.0.rc2]

- Implement confirmation dialog for sensitive admin UI actions

## [1.0.0.rc1]

- Improve performance of loading original events when resolve_link_tos: true option is provided
- Adjust `partitions` table indexes
- Implement admin web UI. So far two pages were implemented - events search and subscriptions

## [0.10.2] - 2024-03-13

- Review the approach to resolve link events
- Fix subscriptions restart interval option not being processed correctly

## [0.10.1] - 2024-03-12

- Handle edge case when creating partitions

## [0.10.0] - 2024-03-12

- Reimplement db structure
- Optimize `#append_to_stream` method - it now produces one `INSERT` query when publishing multiple events

## [0.9.0] - 2024-02-23

- Use POSIX locale for streams and event types

## [0.8.0] - 2024-02-20

- Allow float values for `subscription_pull_interval`. The default value of it was also set to `1.0`(it was `2` previously)

## [0.7.2] - 2024-02-14

- Fix the implementation for PostgreSQL v11

## [0.7.1] - 2024-02-09

- Fix rake tasks

## [0.7.0] - 2024-02-09

- Refactor `pg_eventstore:create` and `pg_eventstore:drop` rake tasks. They now actually create/drop the database. You will have to execute `delete from migrations where number > 6` query before deploying this version.
- Drop legacy migrations

## [0.6.0] - 2024-02-08

- Add stream info into `PgEventstore::WrongExpectedRevisionError` error details

## [0.5.3] - 2024-02-07

- Fix `pg_eventstore:drop` rake task

## [0.5.2] - 2024-02-06

- Improve speed of `PgEventstore::Stream#eql?` a bit

## [0.5.1] - 2024-02-06

- Fix `PgEventstore::Stream` to be properly recognizable inside Hash

## [0.5.0] - 2024-02-05

- Fix event class resolving when providing `resolve_link_tos: true` option
- Return correct stream revision of the `Event#stream` object of the appended event
- Implement events linking feature
- Implement paginated read
- Remove duplicated `idx_events_event_type_id` index

## [0.4.0] - 2024-01-29

- Implement asynchronous subscriptions. Refer to the documentation for more info

## [0.3.0] - 2024-01-24

- Log SQL queries when `PgEvenstore.logger` is set and it is in `:debug` mode

## [0.2.6] - 2023-12-20

- Remove `events.type` column

## [0.2.5] - 2023-12-20

- Fix bug when migrations files are returned in unsorted order on some systems

## [0.2.4] - 2023-12-20

Due to performance issues under certain circumstances, searching by event type was giving bad performance. I decided to extract `type` column from `events` table into separated table. **No breaking changes in public API though.**

**Warning** The migrations this version has, requires you to shut down applications that use `pg_eventstore` and only then run `rake pg_eventstore:migrate`.

## [0.2.3] - 2023-12-18

- Fix performance when searching by event type only(under certain circumstances PosetgreSQL was picking wrong index).

## [0.2.2] - 2023-12-14

- Fix `pg_eventstore:drop` rake task to also drop `migrations` table

## [0.2.1] - 2023-12-14

Under certain circumstances `PG::TRSerializationFailure` exception wasn't retried. Adjust connection's states list to fix that.

## [0.2.0] - 2023-12-14

- Improve performance by reviewing indexes
- Implement migrations

Please run `rake pg_eventstore:migrate` to migrate eventstore db to actual version.

## [0.1.0] - 2023-12-12

Initial release.

- Implement Read command
- Implement AppendToStream command
- Implement Multiple command
