# The description of Event and Stream definitions

`pg_eventstore` provides classes to prepare the events to be inserted into the eventstore. The most important are:

- `PgEventstore::Event` class which represents an event object
- `PgEventstore::Stream` class which represents a stream object

## Event object and its defaults

`PgEventstore::Event` has the following attributes:

- `id` - `String`(UUIDv7, optional, not `nil`, default is `SecureRandom.uuid_v7`). Application-specific identifier, may
  be used by some middlewares. Uniqueness is not guaranteed on the database level, but you can rely on
  `SecureRandom.uuid_v7` as a source of unique values.
- `type` - `String`(optional, not `nil`). Default is an event's class name. Types which start from `$` indicate system
  events. It is not recommended to prefix your events types with `$` sign.
- `global_position` - Integer(optional, read only). Event's global position in the eventstore, aka the "all" stream
  position (inspired by the popular EventstoreDB). Manually assigning this attribute has no effect. It is internally set
  when writing events into the database.
- `stream` - `PgEventstore::Stream`(optional, read only). A Stream an event belongs to, see description below. Manually
  assigning this attribute has no effect. It is internally set when appending an event to the given stream or when
  reading events from the database.
- `stream_revision` - `Integer`(optional, read only). Stream revision at the given event
- `data` - Hash(optional). Event's payload data. For example, if you have a `DescriptionChanged` event class, then you
  may want to have a description value in the event payload data. Example:
  `DescriptionChanged.new(data: { 'description' => 'Description of something', 'post_id' => SecureRandom.uuid_v7 })`
- `markers` - Array of strings(optional). Event markers. You can supply new events with markers list. Persisted events
  contain assigned markers in this attribute. Example: `PgEventstore::Event.new(markers: %w[foo bar])`
- `feature_markers` - `Array<PgEventstore::FeatureMarker>`(optional). Event markers, assigned by a middleware(or any
  other external implementation), but is not going to be persisted along with the rest markers into the default markers
  metadata key and won't be automatically available under `#markers` when reading events. The main reason for that is to
  split event type-related markers and feature-specific markers. Your implementation is responsible for serializing and 
  deserializing those markers. You can see the example of such implementation by inspecting
  `PgEventstore::Middleware::EventTracing` middleware.
- `metadata` - `Hash`(optional). Event metadata. Event meta information which is not part of an events data payload.
  Example: `{ published_by: publishing_user.id }`
- `link_global_position` - `Integer`(optional, read only). If an event is a link event (link events are pointers to
  other events), this attribute contains a `global_position` of the original event. Manually assigning this attribute
  has no effect. It is internally set when linking an event to the given stream or when reading events from the
  database.
- `link_partition_id` - `Integer`(optional, read only). If an event is a link event - this attribute contains a
  partition `id` of original event. Manually assigning this attribute has no effect. It is internally set when appending
  an event to the given stream or when reading events from the database.
- `link` - `PgEventstore::Event`(optional, read only). When reading from a stream using `resolve_link_tos: true`, if an
  event is resolved from a link - this attribute contains a `PgEventstore::Event` object which corresponds to that link.
  Manually assigning this attribute has no effect. It is internally set when reading events from the database.
- `created_at` - `Time`(optional, read only). Database's timestamp when an event was appended to a stream. You may want
  to put your own timestamp into a `metadata` attribute - it may be useful when migrating between different databases.
  Manually assigning this attribute has no effect. It is internally set when appending an event to the given stream or
  when reading events from the database.
- `caused_by` - `PgEventstore::Event`(optional). This is a part of event tracing feature(not configured by default).
  Pass your persisted event to make your unpersisted event be marked as an event, caused by the given persisted event,
  thus, creating causation dependency between them
- `correlation_id` - `String`(UUIDv7, optional). This is a part of event tracing feature(not configured by default). All
  connected events are marked with the same correlation id. Thus, you can fetch all connected events at once.
- `causation_id` - `String`(UUIDv7, optional). This is a part of event tracing feature(not configured by default). The
  id of an event caused current event be persisted.

Example:

```ruby
PgEventstore::Event.new(data: { 'foo' => 'bar' }, type: 'FooChanged')
```

## Stream object

To be able to manipulate a stream, you have to compute a stream's object first. It can be achieved by using the
`PgEventstore::Stream` class. Here is a description of its attributes:

- `context` - String(required). A Bounded Context, read more [here](https://martinfowler.com/bliki/BoundedContext.html).
  Values which start from `$` sign are reserved by `pg_eventstore`. Such contexts can't be used to append events.
- `stream_name` - String(required). A stream name.
- `stream_id` - String(required). A stream id.
- `stream_revision` - Integer(optional, read only). Current stream revision
- `starting_position` - Integer(optional, read only). Global position of the first event in the stream

Example:

```ruby
PgEventstore::Stream.new(context: 'Sales', stream_name: 'Customer', stream_id: '1')
PgEventstore::Stream.new(context: 'Sales', stream_name: 'Customer', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
```

### "all" stream

There is a special stream, called the "all" stream. You can get this object by calling the
`PgEventstore::Stream.all_stream` method. Read more about the "all" stream in the `Reading from the "all" stream`
section of [Reading events](reading_events.md) chapter.
