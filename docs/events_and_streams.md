# The description of Event and Stream definitions

`pg_eventstore` provides classes to manipulate the data in the database. The most important are:

- `PgEventstore::Event` class which represents an event object
- `PgEventstore::Stream` class which represents a stream object

## Event object and its defaults

`PgEventstore::Event` has the following attributes:

- `id` - UUIDv4(optional). If no provided - the value will be autogenerated.
- `type` - String(optional). Default is an event's class name.
- `global_position` - Integer(optional, read only). Event's position in "all" stream. Manually assigning this attribute will affect on nothing. It is internally set when reading events from the database.
- `context` - String(optional, read only). A Bounded Context, read more [here](https://martinfowler.com/bliki/BoundedContext.html). Manually assigning this attribute will affect on nothing. It is internally set when appending an event to the given stream or when reading events from the database.
- `stream_name` - String(optional, read only). Stream's name. Manually assigning this attribute will affect on nothing. It is internally set when appending an event to the given stream or when reading events from the database.
- `stream_id` - String(optional, read only). Stream's id. Manually assigning this attribute will affect on nothing. It is internally set when appending an event to the given stream or when reading events from the database.
- `stream_revision` - Integer(optional, read only). A revision of an event inside its stream.
- `data` - Hash(optional). Event's data. Usually you may want to put here the data which is directly related to an event's type. For example, if you have `DescriptionChanged` event class, then you may want to have a description value in the `data` attribute. Example: `DescriptionChanged.new(data: { 'description' => 'Description of something', 'post_id' => 1 })`
- `metadata` - Hash(optional). Event's metadata. Usually you may want to have some "system" information about an event. Simply saying - and info which doesn't meaningfully suitable to be placed under `data` attribute.
- `link_id` - Integer(optional, read only). If an event is a link event(link events are simply pointers to another events) - this attribute will be containing `global_position` of an original event. Manually assigning this attribute will affect on nothing. It is internally set when appending an event to the given stream or when reading events from the database.
- `created_at` - Time(optional, read only). Database's timestamp when an event was appended to a stream. You may want to put your own timestamp into a `metadata` attribute - it may be useful when migrating between different databases. Manually assigning this attribute will affect on nothing. It is internally set when appending an event to the given stream or when reading events from the database.

Example:

```ruby
PgEventstore::Event.new(data: { 'foo' => 'bar' })
```

## Stream object

To be able to manipulate a stream - you have to compute a stream's object first. It can be achieved by using `PgEventstore::Stream` class. Here is a description of its attributes:

- `context` - String(required). A Bounded Context, read more [here](https://martinfowler.com/bliki/BoundedContext.html).
- `stream_name` - String(required). A stream name
- `stream_id` - String(required). A stream id

Example:

```ruby
PgEventstore::Stream.new(context: 'Sales', stream_name: 'Customer', stream_id: '1')
```