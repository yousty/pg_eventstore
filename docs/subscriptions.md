# Subscriptions

In order to process new events in your microservices you have to have the ability to listen for them. `pg_eventstore` implements a subscription feature for this matter. It is implemented as a background thread that pulls new events according to your filters from time to time (see `subscription_pull_interval` setting option under [**Configuration**](configuration.md) chapter).

## PgEventstore::Subscription

`pg_eventstore` stores various subscription information in the database. The corresponding object that describes the database records is the `PgEventstore::Subscription` object. It is used in the `config.subscription_restart_terminator` setting for example. You can find its attributes summary [here](https://rubydoc.info/gems/pg_eventstore/PgEventstore/Subscription).  

## PgEventstore::SubscriptionsSet

`pg_eventstore` also stores information about which subscriptions are set. The corresponding object that describes the database records is `PgEventstore::SubscriptionsSet`. You can find its attributes summary [here](https://rubydoc.info/gems/pg_eventstore/PgEventstore/SubscriptionsSet).

This record is created when you start your subscriptions. All subscriptions created using a single subscriptions manager instance are locked using a single `PgEventstore::SubscriptionsSet`. When subscriptions are locked, they can't be managed anywhere else. When you stop your subscriptions, the `PgEventstore::SubscriptionsSet` is deleted, unlocking the subscriptions. The `SubscriptionSet` also holds information about the state, number of restarts, the restart interval and last error of the background runner which is responsible for pulling the subscription's events. You can set the max number of restarts and the restarts interval of your subscriptions set via `config.subscriptions_set_max_retries` and `config.subscriptions_set_retries_interval` settings. See [**Configuration**](configuration.md) chapter for more info.

## Creating a subscription

First step you need to do is to create a `PgEventstore::SubscriptionsManager` object and provide the `subscription_set` keyword argument. Optionally you can provide a config name to use, override the `config.subscriptions_set_max_retries` and `config.subscriptions_set_retries_interval` settings:

```ruby
subscriptions_manager = PgEventstore.subscriptions_manager(subscription_set: 'SubscriptionsOfMyAwesomeMicroservice')
another_subscriptions_manager = PgEventstore.subscriptions_manager(:my_custom_config, subscription_set: 'SubscriptionsOfMyAwesomeMicroservice', max_retries: 5, retries_interval: 2)
```

The required `subscription_set` option groups your subscriptions into a set. For example, you could refer to your service's name in the subscription set name.

Now we can use the `#subscribe` method to create the subscription:

```ruby
subscriptions_manager.subscribe('MyAwesomeSubscription', handler: proc { |event| puts event })
```

First argument is the subscription's name. **It must be unique within the subscription set**. Second argument is your subscription's handler where you will be processing your events as they arrive. The example shows the minimum set of arguments required to create the subscription. 

In the given state it will be listening to all events from all streams. You can define various filters by providing the `:filter` key of `options` argument:

```ruby
subscriptions_manager.subscribe(
  'MyAwesomeSubscription', 
  handler: proc { |event| puts event }, 
  options: { filter: { streams: [{ context: 'MyAwesomeContext' }], event_types: ['Foo', 'Bar'] } }
)
```

`:filter` supports the same options as the `#read` method supports when reading from the `"all"` stream. See [*"all" stream filtering*](reading_events.md#all-stream-filtering) section of **Reading events** chapter.

After you added all necessary subscriptions, it is time to start them:

```ruby
subscriptions_manager.start
```

After calling `#start` all subscriptions are locked behind the given subscription set and can't be locked by any other subscription set. This measure is needed to prevent running the same subscription under the same subscription set using different processes/subscription managers. Such situation will lead to a malformed subscription state and will break its position, meaning the same event will be processed several times.

To "unlock" the subscription you should gracefully stop the subscription manager:

```ruby
subscriptions_manager.stop
```

If you shut down the process which runs your subscriptions without calling the `#stop` method, subscriptions will remain locked, and the only way to unlock them will be to call the `#force_lock!` method before calling the `#start` method:

```ruby
subscriptions_manager.force_lock!
subscriptions_manager.start
```

A complete example of the subscription setup process looks like this:

```ruby
require 'pg_eventstore'

PgEventstore.configure do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI') { 'postgresql://postgres:postgres@localhost:5532/eventstore' }  
end

subscriptions_manager = PgEventstore.subscriptions_manager(subscription_set: 'MyAwesomeSubscriptions')
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
subscriptions_manager.force_lock! if ENV['FORCE_LOCK'] == 'true'
subscriptions_manager.start

Kernel.trap('TERM') do
  puts "Received TERM signal. Stopping Subscriptions Manager and exiting..."
  # It is important to wrap subscriptions_manager.stop into another Thread, because it uses Thread::Mutex#synchronize
  # internally, but its usage is not allowed inside Kernel.trap block
  Thread.new { subscriptions_manager.stop }.join
  exit
end

loop do
  sleep 5
  subscriptions_manager.subscriptions.each do |subscription|
    puts <<~TEXT
      Subscription <<#{subscription.name.inspect}>> is at position #{subscription.current_position}. \
      Events processed: #{subscription.total_processed_events}
    TEXT
  end
  puts "Current SubscriptionsSet: #{subscriptions_manager.subscriptions_set}"
  puts ""
end
```

You can save this script in `subscriptions.rb`, run it with `bundle exec ruby subscriptions.rb`, open another ruby console and test posting different events:

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

You will then see the output of your subscription handlers. To gracefully stop the subscriptions process, use `kill -TERM <pid>` command.

## Overriding Subscription config values

You can override `subscription_pull_interval`, `subscription_max_retries`, `subscription_retries_interval` and `subscription_restart_terminator` config values (see [**Configuration**](configuration.md) chapter for details) for the specific subscription by providing the corresponding arguments. Example:

```ruby
subscriptions_manager.subscribe(
  'MyAwesomeSubscription', 
  handler: proc { |event| puts event },
  # overrides config.subscription_pull_interval
  pull_interval: 1,
  # overrides config.subscription_max_retries
  max_retries: 10,
  # overrides config.subscription_retries_interval
  retries_interval: 2,
  # overrides config.subscription_restart_terminator
  restart_terminator: proc { |subscription| subscription.last_error['class'] == 'NoMethodError' }, 
)
```

## Middlewares

If you would like to skip some of your registered middlewares from processing events after they are being pulled by the subscription, you should use the `:middlewares` argument which allows you to override the list of middlewares you would like to use.

Let's say you have these registered middlewares:

```ruby
PgEventstore.configure do |config|
  config.middlewares = { foo: FooMiddleware.new, bar: BarMiddleware.new, baz: BazMiddleware.new }
end
```

And you want to skip `FooMiddleware` and `BazMiddleware`. You simply have to provide an array of corresponding middleware keys you would like to use when creating the subscription:

```ruby
subscriptions_manager.subscribe('MyAwesomeSubscription', handler: proc { |event| puts event }, middlewares: %i[bar])
```

See the [Writing middleware](writing_middleware.md) chapter for info about what is middleware and how to implement it.

## How many subscriptions I should put in one process?

It depends on the nature of your subscription handlers. If they spend more time on ruby code execution than on IO operations, you should limit the number of subscriptions per single process. This can be especially noticed when you rebuild the read models of your microservice, processing all events from the start.
