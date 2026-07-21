# Subscriptions

In order to process new events in your microservices you have to have the ability to listen for them. `pg_eventstore`
implements a subscription feature for this matter. It is implemented as a background thread that pulls new events
according to your filters from time to time (see `subscription_pull_interval` setting option under [**Configuration
**](configuration.md) chapter).

## PgEventstore::Subscription

`pg_eventstore` stores various subscription information in the database. The corresponding object that describes the
database records is the `PgEventstore::Subscription` object. It is used in the `config.subscription_restart_terminator`
setting for example. You can find its attributes
summary [here](https://rubydoc.info/gems/pg_eventstore/PgEventstore/Subscription).

## PgEventstore::SubscriptionsSet

`pg_eventstore` also stores information about which subscriptions are set. The corresponding object that describes the
database records is `PgEventstore::SubscriptionsSet`. You can find its attributes
summary [here](https://rubydoc.info/gems/pg_eventstore/PgEventstore/SubscriptionsSet).

This record is created when you start your subscriptions. All subscriptions created using a single subscriptions manager
instance are locked using a single `PgEventstore::SubscriptionsSet`. When subscriptions are locked, they can't be
managed anywhere else. When you stop your subscriptions, the `PgEventstore::SubscriptionsSet` is deleted, unlocking the
subscriptions. The `SubscriptionSet` also holds information about the state, number of restarts, the restart interval
and last error of the background runner which is responsible for pulling the subscription's events. You can set the max
number of restarts and the restarts interval of your subscriptions set via `config.subscriptions_set_max_retries` and
`config.subscriptions_set_retries_interval` settings. See [**Configuration**](configuration.md) chapter for more info.

## Creating a subscription

First step you need to do is to create a `PgEventstore::SubscriptionsManager` object and provide the `subscription_set`
keyword argument. Optionally you can provide a config name to use, override the `config.subscriptions_set_max_retries`
and `config.subscriptions_set_retries_interval` settings:

```ruby
subscriptions_manager = PgEventstore.subscriptions_manager(subscription_set: 'SubscriptionsOfMyAwesomeMicroservice')
another_subscriptions_manager = PgEventstore.subscriptions_manager(
  :my_custom_config, subscription_set: 'SubscriptionsOfMyAwesomeMicroservice', max_retries: 5, retries_interval: 2
)
```

The required `subscription_set` option groups your subscriptions into a set. For example, you could refer to your
service's name in the subscription set name.

Now we can use the `#subscribe` method to create the subscription:

```ruby
subscriptions_manager.subscribe('MyAwesomeSubscription', handler: proc { |event| puts event })
```

First argument is the subscription's name. **It must be unique within the subscriptions set**. Second argument is your
subscription's handler where you will be processing your events as they arrive. The example shows the minimum set of
arguments required to create the subscription.

After you added all necessary subscriptions, it is time to start them:

```ruby
subscriptions_manager.start
# => PgEventstore::BasicRunner
```

After calling `#start` all subscriptions are locked behind the given subscriptions set and can't be locked by any other
subscriptions set. This measure is needed to prevent running the same subscription under the same subscription set using
different processes/subscription managers. Such situation will lead to a malformed subscription state and will break its
position, meaning the same event will be processed several times.

If, for some reason, you want to lock already locked subscription - you can provide `force_lock: true`:

```ruby
subscriptions_manager = PgEventstore.subscriptions_manager(
  subscription_set: 'SubscriptionsOfMyAwesomeMicroservice', force_lock: true
)
subscriptions_manager.start
```

A complete example of the subscription setup process looks like this:

```ruby
PgEventstore.configure do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI') { 'postgresql://postgres:postgres@localhost:5532/eventstore' }
end

subscriptions_manager = PgEventstore.subscriptions_manager(
  subscription_set: 'MyAwesomeSubscriptions'
)
subscriptions_manager.subscribe(
  'Foo events Subscription',
  handler: proc { |event| p "Foo events Subscription: #{event.inspect}" },
  options: { filter: { event_types: ['Foo'] } }
)
subscriptions_manager.subscribe(
  '"BarCtx" context Subscription',
  handler: proc { |event| p "'BarCtx' context Subscription: #{event.inspect}" },
  options: { filter: { streams: [{ context: 'BarCtx' }] }
  }
)
subscriptions_manager.start
```

Persist this script into a file(let's say `subscriptions.rb`). Now it is time to start the process which will be
processing those subscriptions. `pg_eventstore` has CLI for that purpose:

```bash
# -r ./subscriptions.rb will load our subscriptions definitions
pg-eventstore subscriptions start -r ./subscriptions.rb
```

After running that test subscriptions you can open another ruby console and test posting different events:

```ruby
require 'pg_eventstore'

PgEventstore.configure do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI') { 'postgresql://postgres:postgres@localhost:5532/eventstore' }
end

foo_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeStream', stream_id: '1')
bar_stream = PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'MyAwesomeStream', stream_id: '1')
PgEventstore.client.append_to_stream(foo_stream, PgEventstore::Event.new(type: 'Foo', data: { foo: :bar }))
PgEventstore.client.append_to_stream(bar_stream, PgEventstore::Event.new(type: 'Foo', data: { foo: :bar }))
```

You will then see the output of your subscription handlers. To gracefully stop the subscriptions process, use
`kill -TERM <pid>` command.

### Filtering events

To listen to the specific events you have to supply `:filter` option. Example:

```ruby
subscriptions_manager.subscribe(
  'MyAwesomeSubscription',
  handler: proc { |event| puts event },
  options: { filter: { streams: [{ context: 'FooCtx' }], event_types: %w[Foo Bar] } }
)
```

Filtering events of a subscription is the same as filtering events when [reading from "all" stream](reading_events.md#all-stream-filtering),
but with some additions:
- there is no limitations on markers filter. The next is all allowed:
```ruby
# Listen to all events from 'FooCtx' context, marked with 'foo' marker
subscriptions_manager.subscribe(
  'Sub1',
  handler: proc { |event| puts event },
  options: { filter: { streams: [{ context: 'FooCtx' }], event_types: [{ markers: ['foo'] }] } }
)
# Listen to all events from 'FooCtx' context & 'Foo' stream name, marked with 'foo' marker
subscriptions_manager.subscribe(
  'Sub2',
  handler: proc { |event| puts event },
  options: { filter: { streams: [{ context: 'FooCtx', stream_name: 'Foo' }], event_types: [{ markers: ['foo'] }] } }
)
```
- you can filter event types by prefixes. In the next example the subscription will catch all events with event types
starting from `'Foo'`(e.g. `'FooBar'`, `'Foo1'`, `'Foosomethingelse'`, etc):
```ruby
# Listen to all events from 'FooCtx' context, marked with 'foo' marker
subscriptions_manager.subscribe(
  'Sub1',
  handler: proc { |event| puts event },
  options: { filter: { streams: [{ context: 'FooCtx' }], event_types: [{ prefix: 'Foo' }] } }
)
```

### Subscription position

Internally, each event has its own subscription position assigned. This happens in the background process with
`config.events_subscription_position_update_interval` interval(in seconds) whenever you start any subscription. The
algorithm of assigning of event subscription position is deterministic and events processing by subscriptions based on
that value is idempotent. The event subscription position ordering may differ from `Event#global_position` ordering, but
it correlates with a stream revision ordering inside a single stream, meaning that an event with stream revision `0`
can't be processed earlier than event with stream revision `1` if they both belong to the same stream.

Let's say you never run subscriptions, and you have now plenty of events without an assigned subscription position. What
will happen if you start any subscription? The worker which is responsible for assigning those positions will need to
process every existing event. It does so in batches of 100k records(current implementation), each batch takes 1-2
seconds to finish(depending on your hardware). Thus, if your subscription targets some events farther from the beginning
of your events history - it will require some time to get there.

#### Setting starting position

You can set the initial position of new subscription to start with:

```ruby
subscriptions_manager.subscribe(
  'MyAwesomeSubscription',
  handler: proc { |event| puts event },
  options: { from_position: 100 }
)
```

This allows to jump to the certain position to start with and skip unwanted events. Please note that **this is not** an
`Event#global_position` value, but rather subscription position of the event. You can find corresponding subscription
position of an event in admin web UI.

Unlike `:from_position` of Read API - `:from_position` in Subscriptions API is **exclusive**. For example, if you have
events with positions 100, 101 and 102, setting `:from_position` to 100 will result in processing event at position 101.

## Overriding Subscription config values

You can override `subscription_pull_interval`, `subscription_max_retries`, `subscription_retries_interval`,
`subscription_restart_terminator`, `failed_subscription_notifier` and `subscription_graceful_shutdown_timeout` config
values (see [**Configuration**](configuration.md) chapter for details) for the specific subscription by providing the
corresponding arguments. Example:

```ruby
subscriptions_manager.subscribe(
  'MyAwesomeSubscription',
  handler: proc { |event| puts event },
  # overrides config.subscription_pull_interval
  pull_interval: 0.5,
  # overrides config.subscription_max_retries
  max_retries: 10,
  # overrides config.subscription_retries_interval
  retries_interval: 2,
  # overrides config.subscription_restart_terminator
  restart_terminator: proc { |subscription| subscription.last_error['class'] == 'NoMethodError' },
  # overrides config.failed_subscription_notifier
  failed_subscription_notifier: proc { |_subscription, err| p err },
  # overrides config.subscription_graceful_shutdown_timeout
  graceful_shutdown_timeout: 20,
  # Yield array of events into your handler instead a single event. See example bellow.
  in_batches: true
)
```

## Processing events in batches

There is an ability to tell the subscription to yield an array of events it pulled last time. The number of events is
the implementation specific(current implementation may yield up to 1k events) and can't be adjusted. Example:

```ruby
subscriptions_manager.subscribe(
  'MyAwesomeSubscription',
  handler: proc { |events| puts events }, # => outputs array of events
  in_batches: true
)
```

In this case the subscription's position will be advanced to the position of the last event of the chunk. Please note
that in case of failure the whole chunk will be yielded again during subscription retries phase.

## Middlewares

If you would like to skip some of your registered middlewares from processing events after they are being pulled by the
subscription, you should use the `:middlewares` argument which allows you to override the list of middlewares you would
like to use.

Let's say you have these registered middlewares:

```ruby
PgEventstore.configure do |config|
  config.middlewares = { foo: FooMiddleware.new, bar: BarMiddleware.new, baz: BazMiddleware.new }
end
```

And you want to skip `FooMiddleware` and `BazMiddleware`. You simply have to provide an array of corresponding
middleware keys you would like to use when creating the subscription:

```ruby
subscriptions_manager.subscribe('MyAwesomeSubscription', handler: proc { |event| puts event }, middlewares: %i[bar])
```

See the [Writing middleware](writing_middleware.md) chapter for info about what is middleware and how to implement it.

## How many subscriptions I should put in one process?

It depends on the nature of your subscription handlers. If they spend more time on ruby code execution than on IO
operations, you should limit the number of subscriptions per single process. This can be especially noticed when you
rebuild the read models of your microservice, processing all events from the start.

## Few words about a subscription handler

It is recommended your subscription handler be idempotent. The subscription implementation tries hard not to process the
same event multiple times. The internal implementation is next:

- fetch an event from the database
- pass it into subscription's handler
- advance the subscription's position

These steps are not atomic, and anything can happen in between the second and the third steps. In this case the same
event may be processed multiple times until the whole process succeeds. In this case the implementation guarantees the
processed event will never be processed again after the subscription's position was persisted (unless you reset the
subscription position of course).
