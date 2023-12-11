# Configuration

Configuration options:

| name                    | value    | default value                                                | description                                                                                                                                                                                                                                                            |
|-------------------------|----------|--------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| pg_uri                  | String   | `'postgresql://postgres:postgres@localhost:5432/eventstore'` | PostgreSQL connection string. See PostgreSQL [docs](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING-URIS) for more information.                                                                                                            |
| max_count               | Integer  | `1000`                                                       | Number of events to return in one response when reading from a stream.                                                                                                                                                                                                 |
| middlewares             | Array    | `[]`                                                         | Array of objects that respond to `#serialize` and `#deserialize` methods. See [**Writing middleware**](writing_middleware.md) chapter.                                                                                                                                 |
| event_class_resolver    | `#call`  | `PgEventstore::EventClassResolver.new`                       | A `#call`-able object that accepts a string and returns an event's class. See **Resolving events classes** chapter bellow for more info.                                                                                                                               |
| logger                  | `Logger` | `nil`                                                        | A logger that logs messages from `pg_eventstore` gem.                                                                                                                                                                                                                  |
| connection_pool_size    | Integer  | `5`                                                          | Max number of connections per ruby process. It must equal the number of threads of your application.                                                                                                                                                                   |
| connection_pool_timeout | Integer  | `5`                                                          | Time in seconds to wait for the connection in pool to be released. If no connections are available during this time - `ConnectionPool::TimeoutError` will be raised. See `connection_pool` gem [docs](https://github.com/mperham/connection_pool#usage) for more info. |

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
