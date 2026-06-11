# How it works

## Database architecture

The database is designed specifically for Eventsourcing alongside Domain-Driven Design. Internally, it is architected
using Snowflake schema with `events_global_index` as fact table and `events`, `streams_global_index` and `partitions`
tables as dimensions tables. `events` table is additionally partitioned in next way:

- For each `Stream#context` there is a subpartition of `events` table. Those tables have `contexts_` prefix.
- For each `Stream#stream_name` there is a subpartition of `contexts_` table. Those tables have `stream_names_` prefix.
- For each `Event#type` there is a subpartition of `stream_names_` table. Those tables have `event_types_` prefix.

To implement partitions - Declarative Partitioning is used. While the implementation scales well with the number of
partitions - it is recommended your application pre-defines all combinations of contexts, stream names and event types.
More about PostgreSQL partitions is [here](https://www.postgresql.org/docs/current/ddl-partitioning.html).

So, let's say you want to publish next event:

```ruby
stream = PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1')
event = PgEventstore::Event.new(type: 'SomethingChanged', data: { foo: :bar })
PgEventstore.client.append_to_stream(stream, event)
```

To actually create `events` record next partitions will be created:

- `contexts_81820a` table which is a subpartition of `events` table. It is needed to handle all events which comes to
  `"SomeCtx"` context
- `stream_names_ecb803` table which is a subpartition of `contexts_81820a` table. It is needed to handle all events
  which comes to `"SomeStream"` stream name of `"SomeCtx"` context
- `event_types_aeadd5` table which is a subpartition of `stream_names_ecb803` table. It is needed to handle all events
  which have `"SomethingChanged"` event type of `"SomeStream"` stream name of `"SomeCtx"` context

You can check all partitions and associated with them contexts, stream names and event types by querying special service
table called `partitions`. Example(based on the sample above):

```ruby
PgEventstore.connection.with do |conn|
  conn.exec('select * from partitions')
end.to_a
# =>
#   [{"id"=>1, "context"=>"SomeCtx", "stream_name"=>nil, "event_type"=>nil, "table_name"=>"contexts_81820a"},
#    {"id"=>2, "context"=>"SomeCtx", "stream_name"=>"SomeStream", "event_type"=>nil, "table_name"=>"stream_names_ecb803"},
#    {"id"=>3, "context"=>"SomeCtx", "stream_name"=>"SomeStream", "event_type"=>"SomethingChanged", "table_name"=>"event_types_aeadd5"}]
```

### PostgreSQL settings

The more partitions you have, the more locks are required for operations that affect multiple partitions. Especially it
concerns the case when you involve many different event types when using `Client#multiple`. It may lead to the next
error:

```
ERROR:  out of shared memory (PG::OutOfMemory)
HINT:  You might need to increase max_pred_locks_per_transaction.
```

PostgreSQL suggests to increase the `max_pred_locks_per_transaction`(the description of it
is [here](https://www.postgresql.org/docs/current/runtime-config-locks.html)). The default value is `64`. In case you
have several thousands of partitions - you may want to set it to `128` or even to `256`.

You may also face similar error which refers to `max_locks_per_transaction` setting:

```
PG::OutOfMemory: ERROR:  out of shared memory (PG::OutOfMemory)
HINT:  You might need to increase "max_locks_per_transaction".
```

The reason of it to appear is the same - too many objects(partition tables, indexes, etc) are involved in a single
transaction. You may face it when running migrations on large pg_eventstore database using `rake pg_eventstore:migrate`
as some migrations may involve high number of db objects.

Conclusion: adjust values of `max_locks_per_transaction` and `max_pred_locks_per_transaction` settings as long as the
number of partitions(number of distinct values of (context, stream_name, event type) tuple) grow.

## Appending events and multiple commands

You may want to get familiar with [Appending events](appending_events.md) and [multiple commands](multiple_commands.md)
first.

`pg_eventstore` internally uses `Serializable` transaction isolation level(more about different transaction isolation
levels in PostgreSQL is [here](https://www.postgresql.org/docs/current/transaction-iso.html)). On practice this means
that any transaction may fail with serialization error, and the common approach is to restart this transaction. For ruby
this means re-execution of the block of code. Which is why there is a warning regarding potential block re-execution
when using `#multiple`. However current implementation allows to limit 99% of retries to the manipulations with one
stream. For example, when two parallel processes changing the same stream. If different streams are being changed at the
same time - it is less likely it would perform retry.

Examples:

- if "process 1" and "process 2" perform the append command at the same time - one of the append commands will be
  retried:

```ruby
# process 1
stream = PgEventstore::Stream.new(context: 'MyCtx', stream_name: 'MyStream', stream_id: '1')
event = PgEventstore::Event.new(type: 'SomethingChanged', data: { foo: :bar })
PgEventstore.client.append_to_stream(stream, event)

# process 2
stream = PgEventstore::Stream.new(context: 'MyCtx', stream_name: 'MyStream', stream_id: '1')
event = PgEventstore::Event.new(type: 'SomethingElseChanged', data: { baz: :bar })
PgEventstore.client.append_to_stream(stream, event)
```

- if "process 1" performs multiple commands at the same time "process 2" performs append command which involves the same
  stream from "process 1" - either block of `#multiple` or `#append_to_stream` will be retried:

```ruby
# process 1
stream1 = PgEventstore::Stream.new(context: 'MyCtx', stream_name: 'MyStream1', stream_id: '1')
stream2 = PgEventstore::Stream.new(context: 'MyCtx', stream_name: 'MyStream2', stream_id: '1')
event = PgEventstore::Event.new(type: 'SomethingChanged', data: { foo: :bar })
PgEventstore.client.multiple do
  PgEventstore.client.append_to_stream(stream1, event)
  PgEventstore.client.append_to_stream(stream2, event)
end

# process 2
stream2 = PgEventstore::Stream.new(context: 'MyCtx', stream_name: 'MyStream2', stream_id: '1')
event = PgEventstore::Event.new(type: 'SomethingChanged', data: { foo: :bar })
PgEventstore.client.append_to_stream(stream2, event)
```

Retries also concern your potential implementation of [middlewares](writing_middleware.md). For example,
`YourAwesomeMiddleware#serialize` can be executed several times when append the event. This is especially important when
you involve your microservices here - they can receive the same payload several times.

Conclusion. When developing using `pg_eventstore` - always keep in mind that some parts of your implementation can be
executed several times before successfully publishing an event, or event when reading events(`#deserializa` middleware
method) if you perform reading withing `#multiple` block. 
