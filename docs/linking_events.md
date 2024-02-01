# Linking Events

## Linking single event

You can create a link to an existing event. Next example demonstrates how you can link an existing event from another stream:

```ruby
class SomethingHappened < PgEventstore::Event
end

event = SomethingHappened.new(
  type: 'some-event', data: { title: 'Something happened' }
)

events_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeStream', stream_id: '1')
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeProjection', stream_id: '1')
# Persist our event
event = PgEventstore.client.append_to_stream(events_stream, event)

# Link event into your projection
PgEventstore.client.link_to(projection_stream, event)
```

The linked event can later be fetched by providing the `:resolve_link_tos` option when reading from the stream:

```ruby
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeProjection', stream_id: '1')
PgEventstore.client.read(projection_stream, options: { resolve_link_tos: true })
```

If you don't provide the `:resolve_link_tos` option, the linked event will be returned instead of the original one.

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

events_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeStream', stream_id: '1')
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeProjection', stream_id: SecureRandom.uuid)

event1, event2 = PgEventstore.client.append_to_stream(events_stream, [event1, event2])

# Links first event
PgEventstore.client.link_to(projection_stream, event1, options: { expected_revision: :no_stream })
# Raises PgEventstore::WrongExpectedVersionError error because stream already exists
PgEventstore.client.link_to(projection_stream, event2, options: { expected_revision: :no_stream })
```

## Middlewares

If you would like to modify your link events before they get persisted - you should use the `:middlewares` argument which allows you to pass the list of middlewares you would like to use. **By default no middlewares will be applied to the link event despite on `config.middlewares` option**.

**Warning! It is recommended your middlewares do not change `Event#type` and `Event#link_id`.** Otherwise linking feature will simply not work.

Let's say you have these registered middlewares:

```ruby
PgEventstore.configure do |config|
  config.middlewares = { foo: FooMiddleware.new, bar: BarMiddleware.new, baz: BazMiddleware.new }
end
```

And you want to use `FooMiddleware` and `BazMiddleware`. You simply have to provide an array of corresponding middleware keys you would like to use:

```ruby
events_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeStream', stream_id: '1')
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyAwesomeProjection', stream_id: '1')

event = PgEventstore.client.append_to_stream(events_stream, PgEventstore::Event.new)
PgEventstore.client.link_to(projection_stream, event, middlewares: %i[foo baz])
```

See [Writing middleware](writing_middleware.md) chapter for info about what is middleware and how to implement it.
