# Linking Events

## Linking single event

To create a link on an existing event, you need to have a stream where you want to link that event to and you need to have an event, fetched from the database:

```ruby
class SomethingHappened < PgEventstore::Event
end

event = SomethingHappened.new(
  type: 'some-event', data: { title: 'Something happened' }
)

events_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeStream', stream_id: '1')
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeProjection', stream_id: '1')
event = PgEventstore.client.append_to_stream(events_stream, event)

# Link event into your projection
PgEventstore.client.link_to(projection_stream, event)
```

The linked event can later be fetched by providing the `:resolve_link_tos` option when reading from the stream:

```ruby
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeProjection', stream_id: '1')
PgEventstore.client.read(projection_stream, options: { resolve_link_tos: true })
```

If you don't provide the `:resolve_link_tos` option, the "linked" event will be returned instead of the original one.

## Linking multiple events

You can provide an array of events to link to the target stream:

```ruby
class SomethingHappened < PgEventstore::Event
end

events = 3.times.map { |i| SomethingHappened.new(type: 'some-event', data: { title: "Something happened-#{i}" }) }
events_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeStream', stream_id: '1')
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeProjection', stream_id: '1')
events = PgEventstore.client.append_to_stream(events_stream, events)
# Link events
PgEventstore.client.link_to(projection_stream, events)
```

## Handling concurrency

Linking concurrency is implemented the same way as appending concurrency. You can check [**Handling concurrency**](appending_events.md#handling-concurrency) chapter of **Appending Events** section.

Example:

```ruby
require 'securerandom'
class SomethingHappened < PgEventstore::Event
end

event1 = SomethingHappened.new
event2 = SomethingHappened.new

events_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeStream', stream_id: SecureRandom.uuid)
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeProjection', stream_id: '1')

event1, event2 = PgEventstore.client.append_to_stream(events_stream, [event1, event2])

# Links first event
PgEventstore.client.link_to(projection_stream, event1, options: { expected_revision: :no_stream })
# Raises PgEventstore::WrongExpectedVersionError error because stream already exists
PgEventstore.client.link_to(projection_stream, event2, options: { expected_revision: :no_stream })
```
