# Subscriptions

In order to process new events in your microservices you have to have the ability to listen for them. `pg_eventstore` implements Subscription feature for this matter. It is implemented as a background thread that pulls new events according to your filters from time to time(see `subscription_pull_interval` setting option under [**Configuration**](configuration.md) chapter).

## PgEventstore::Subscription

`pg_eventstore` stores various Subscription information into the database. The corresponding object that describes database record is `PgEventstore::Subscription` object. You can face it when defining `config.subscription_restart_terminator` setting for example. You can find its attributes summary [here](https://rubydoc.info/gems/pg_eventstore/PgEventstore/Subscription).  

## PgEventstore::SubscriptionsSet

Along with Subscription information `pg_eventstore` stores information about subscriptions set. The corresponding object that describes database record is `PgEventstore::SubscriptionsSet`. You can find its attributes summary [here](https://rubydoc.info/gems/pg_eventstore/PgEventstore/SubscriptionsSet).

In general - this record is created when you start your Subscriptions. All Subscriptions get locked using `PgEventstore::SubscriptionsSet#id` value when start happens. When you stop your Subscriptions - `PgEventstore::SubscriptionsSet` is deleted. It also holds the information about the state and last error of the background runner which is responsible for pulling Subscriptions events.

## Creating Subscription

First step you need to do is to create `PgEventstore::SubscriptionsManager` object and provide `subscription_set` keyword argument. Optionally you can provide a config name to use:

```ruby
subscriptions_manager = PgEventstore.subscriptions_manager(subscription_set: 'SubscriptionsOfMyAwesomeMicroservice')
another_subscriptions_manager = PgEventstore.subscriptions_manager(:my_custom_config, subscription_set: 'SubscriptionsOfMyAwesomeMicroservice')
```

The meaning of `subscription_set` value is to group Subscriptions by certain definition. For example, it could be a name of your microservice Subscriptions belong to.

Now we can use `#subscribe` method to create the Subscription:

```ruby
subscriptions_manager.subscribe('MyAwesomeSubscription', handler: proc { |event| puts event })
```

First argument is Subscription's name. **It must be unique within the subscription set**. Second argument - is your Subscription's handler where you will be processing your events as they come. This is the minimum set of arguments to create the Subscription. 

In the given state it will be listening to all events from all streams. You can define various filters by providing `:filter` key of `options` argument:

```ruby
subscriptions_manager.subscribe(
  'MyAwesomeSubscription', 
  handler: proc { |event| puts event }, 
  options: { filter: { streams: [{ context: 'MyAwesomeContext' }], event_types: ['Foo', 'Bar'] } }
)
```

`:filter` supports the same options as `#read` method supports when reading from `"all"` stream. See [*"all" stream filtering*](reading_events.md#all-stream-filtering) section of **Reading events** chapter.

After you added all necessary Subscriptions - it is time to start them:

```ruby
subscriptions_manager.start
```

Upon `#start` - all Subscriptions are "locked" behind the given subscription set and can't be "locked" by any other subscription set. This measure is needed to prevent running the same Subscription under the same subscription set by different processes/subscription managers. Such situation will lead to malformed state of the Subscription, and will break its position, meaning the same event will be processed several times.

To "unlock" the Subscription you should gracefully stop the subscription manager:

```ruby
subscriptions_manager.stop
```

If you shut down the process which runs your Subscriptions without calling the `#stop` method - Subscriptions will remain "locked", and the only way to "unlock" them will be to call `#force_lock!` method before calling `#start` method:

```ruby
subscriptions_manager.force_lock!
subscriptions_manager.start
```

Considering all said, the complete example of Subscriptions process would look like next:

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
      Events processed: #{subscription.events_processed_total}
    TEXT
  end
  puts "Current SubscriptionsSet: #{subscriptions_manager.subscriptions_set}"
  puts ""
end
```

You can save this script under `subscriptions.rb`, run it as `bundle exec ruby subscriptions.rb`, open another ruby console and try posting different events:

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

You will see then the output your Subscriptions handlers produce. To gracefully stop Subscriptions process - use `kill -TERM <pid>` command.

## Overriding Subscription config values

You can override `subscription_pull_interval`, `subscription_max_retries`, `subscription_retries_interval` and `subscription_restart_terminator` config values(see [**Configuration**](configuration.md) chapter for details) for the specific Subscription by providing corresponding arguments. Example:

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

If you would like to skip some of your registered middlewares from processing events after they being pulled by the Subscription - you should use the `:middlewares` argument which allows you to override the list of middlewares you would like to use.

Let's say you have these registered middlewares:

```ruby
PgEventstore.configure do |config|
  config.middlewares = { foo: FooMiddleware.new, bar: BarMiddleware.new, baz: BazMiddleware.new }
end
```

And you want to skip `FooMiddleware` and `BazMiddleware`. You simply have to provide an array of corresponding middleware keys you would like to use when creating the Subscription:

```ruby
subscriptions_manager.subscribe('MyAwesomeSubscription', handler: proc { |event| puts event }, middlewares: %i[bar])
```

See [Writing middleware](writing_middleware.md) chapter for info about what is middleware and how to implement it.

## How much subscriptions I should put in one process?

It depends on the nature of your Subscriptions handlers. If they spend more time on ruby code execution than on IO operations - you should limit the number of Subscriptions per single process. This can be especially noticed when you rebuild your Read Models of your microservice and, thus, going through all events from the start.
