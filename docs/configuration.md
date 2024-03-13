# Configuration

Configuration options:

| name                               | value   | default value                                                | description                                                                                                                                                                                                                                                                                                            |
|------------------------------------|---------|--------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| pg_uri                             | String  | `'postgresql://postgres:postgres@localhost:5432/eventstore'` | PostgreSQL connection string. See PostgreSQL [docs](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING-URIS) for more information.                                                                                                                                                            |
| max_count                          | Integer | `1000`                                                       | Number of events to return in one response when reading from a stream.                                                                                                                                                                                                                                                 |
| middlewares                        | Array   | `{}`                                                         | A hash where a key is a name of your middleware and value is an object that respond to `#serialize` and `#deserialize` methods. See [**Writing middleware**](writing_middleware.md) chapter.                                                                                                                           |
| event_class_resolver               | `#call` | `PgEventstore::EventClassResolver.new`                       | A `#call`-able object that accepts a string and returns an event's class. See **Resolving events classes** chapter bellow for more info.                                                                                                                                                                               |
| connection_pool_size               | Integer | `5`                                                          | Max number of connections per ruby process. It must equal the number of threads of your application. When using subscriptions it is recommended to set it to the number of subscriptions divided by two or greater. See [**Picking max connections number**](#picking-max-connections-number) chapter of this section. |
| connection_pool_timeout            | Integer | `5`                                                          | Time in seconds to wait for a connection in the pool to be released. If no connections are available during this time - `ConnectionPool::TimeoutError` will be raised. See `connection_pool` gem [docs](https://github.com/mperham/connection_pool#usage) for more info.                                               |
| subscription_pull_interval         | Float   | `1.0`                                                        | How often to pull new subscription events in seconds. The minimum meaningful value is `0.2`. Values less than `0.2` will act as it is `0.2`.                                                                                                                                                                           |
| subscription_max_retries           | Integer | `5`                                                          | Max number of retries of failed subscription.                                                                                                                                                                                                                                                                          |
| subscription_retries_interval      | Integer | `1`                                                          | Interval in seconds between retries of failed subscriptions.                                                                                                                                                                                                                                                           |
| subscriptions_set_max_retries      | Integer | `10`                                                         | Max number of retries for failed subscription sets.                                                                                                                                                                                                                                                                    |
| subscriptions_set_retries_interval | Integer | `1`                                                          | Interval in seconds between retries of failed subscription sets.                                                                                                                                                                                                                                                       |
| subscription_restart_terminator    | `#call` | `nil`                                                        | A callable object that accepts `PgEventstore::Subscription` object to determine whether restarts should be stopped(true - stops restarts, false - continues restarts).                                                                                                                                                 |

## Multiple configurations

`pg_eventstore` allows you to have as many configs as you want. This allows you, for example, to have different
databases, or to have a different set of middlewares for specific cases only. To do so, you have to name your
configuration, and later provide that name to `PgEventstore` client.

Setup your configs:

```ruby
PgEventstore.configure(name: :pg_db_1) do |config|
  # adjust your config here
  config.pg_uri = 'postgresql://postgres:postgres@localhost:5432/eventstore'
end
PgEventstore.configure(name: :pg_db_2) do |config|
  # adjust your second config here
  config.pg_uri = 'postgresql://postgres:postgres@localhost:5532/eventstore'
end
```

Tell `PgEventstore` which config you want to use:

```ruby
# Read from "all" stream using :pg_db_1 config
PgEventstore.client(:pg_db_1).read(PgEventstore::Stream.all_stream)
# Read from "all" stream using :pg_db_2 config
PgEventstore.client(:pg_db_2).read(PgEventstore::Stream.all_stream)
```

### Default config

If you have one config only - you don't have to bother naming it or passing a config name to the client when performing
any operations. You can configure it as usual.

Setup your default config:

```ruby
PgEventstore.configure do |config|
  # config goes here
  config.pg_uri = 'postgresql://postgres:postgres@localhost:5432/eventstore'
end
```

Use it:

```ruby

# Read from "all" stream using your default config
EventStoreClient.client.read(PgEventstore::Stream.all_stream)
```

## Resolving event classes

During the deserialization process `pg_eventstore` tries to pick the correct class for an event. By default it does it
using the `PgEventstore::EventClassResolver` class. All it does is `Object.const_get(event_type)`. By default, if you
don't provide the `type` attribute for an event explicitly, it will grab the event's class name, meaning by default:

- event's type is event's class name
- when instantiating an event - `pg_eventstore` tries to lookup an event class based on the value of event's `type`
  attribute with a fallback to `PgEventstore::Event` class

You can override the default event class resolver by providing any `#call`-able object. It should accept event's type
and return event's class based on it. Example:

```ruby
PgEventstore.configure do |config|
  config.event_class_resolver = proc { |event_type| Object.const_get(event_type.gsub('Foo', 'Bar')) rescue PgEventstore::Event }
end
```

## Picking max connections number

A connection is hold from the connection pool to perform the request and it is released back to the connection pool once
the request is finished. If you run into the (theoretical) edge case, when all your application's threads (or
subscriptions) are performing `pg_eventstore` queries at the same time and all those queries take more
than `connection_pool_timeout` seconds to complete, you have to have `connection_pool_size` set to the exact amount of
your application's threads (or to the number of subscriptions when using subscriptions) to prevent timeout errors.
Practically this is not the case, as all `pg_eventstore` queries are pretty fast. So, a good value for
the `connection_pool_size` option is **half the number ** of your application's threads(or half the number of
Subscriptions).

### Exception scenario

If you are using the [`#multiple`](multiple_commands.md) method - you have to take into account the execution time of
the whole block you pass in it. This is because the connection will be released only after the block's execution is
finished. So, for example, if you perform several commands within the block, as well as some API request, the connection
will be release only after all those steps:

```ruby
PgEventstore.client.multiple do
  # Connection is hold from the connection pool
  PgEventstore.client.read(some_stream)
  Stripe::Payment.create(some_attrs)
  PgEventstore.client.append_to_stream(some_stream, some_event)
  # Connection is released
end
```

Taking this into account you may want to increase `connection_pool_size` up to the number of your application's threads(
or subscriptions).

### Usage of external connection pooler

`pg_eventstore` does not use any session-specific features of PostgreSQL. You can use any PostgreSQL connection pooler
you like, such as [PgBouncer](https://www.pgbouncer.org/) for example. 
