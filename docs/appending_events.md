# Appending Events

## Append event

The easiest way to append an event is to create an event object and a stream object and call the client's
`#append_to_stream` method.

```ruby
class SomethingHappened < PgEventstore::Event
end

event = SomethingHappened.new(data: { user_id: '1', title: "Something happened" })
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.append_to_stream(stream, event)
# => #<SomethingHappened:0x000077c654b8f8c0 @readonly=Set[], @id="ecab1317-f2ae-4fc0-ad16-b820cd6fe053", @type="SomethingHappened", @global_position=133486960, @stream=#<PgEventstore::Stream:0x000077c6549e3990 @context="FooCtx", @stream_name="Foo", @stream_id="1", @stream_revision=nil, @starting_position=nil>, @stream_revision=16024, @data={"title" => "Something happened", "user_id" => "1"}, @markers=[], @metadata={}, @link_global_position=nil, @link_partition_id=nil, @link=nil, @created_at=2026-07-08 10:25:12.721906 UTC>
```

## Appending multiple events

You can pass an array of events to the `#append_to_stream` method. This way events will be appended one-by-one. **This
operation is atomic and it guarantees that events are added to the stream in the given order.**

```ruby
class SomethingHappened < PgEventstore::Event
end

event1 = SomethingHappened.new(data: { user_id: '1', title: "Something happened 1" })
event2 = SomethingHappened.new(data: { user_id: '1', title: "Something happened 2" })
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.append_to_stream(stream, [event1, event2])
```

## Handling concurrency

When appending events to a stream you can supply a stream state or stream revision. You can use this to tell
`pg_eventstore` what state or version you expect the stream to be in when you append. If the stream isn't in that state
then an exception will be thrown.

For example if we try to append two records expecting both times that the stream doesn't exist we will get an exception
on the second:

```ruby
class SomethingHappened < PgEventstore::Event
end

event1 = SomethingHappened.new(data: { foo: :bar })
event2 = SomethingHappened.new(data: { bar: :baz })
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: '1')

# Successfully appends an event
PgEventstore.client.append_to_stream(stream, event1, options: { expected_revision: :no_stream })
# Raises PgEventstore::WrongExpectedRevisionError error
PgEventstore.client.append_to_stream(stream, event2, options: { expected_revision: :no_stream })
```

Here are possible values of `:expected_revision` option:

- `:any`. Doesn't perform any checks. This is the default.
- `:no_stream`. Expects a stream to be absent when appending an event
- `:stream_exists`. Expects a stream to be present when appending an event
- a revision number(Integer). Expects a stream to be in the given revision.

This check can be used to implement optimistic concurrency. When you retrieve a stream, you take note of the current
version number, then when you save it back you can determine if somebody else has modified the record in the meantime.

```ruby
class SomethingHappened < PgEventstore::Event
end

stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: '1')
event1 = SomethingHappened.new(data: { foo: :bar })
event2 = SomethingHappened.new(data: { bar: :baz })

# Pre-populate stream with some event
PgEventstore.client.append_to_stream(stream, event1)
# Get the revision number of latest event
revision = PgEventstore.client.read(stream, options: { max_count: 1, direction: 'Backwards' }).first.stream_revision
# Expected revision matches => will succeed
PgEventstore.client.append_to_stream(stream, event2, options: { expected_revision: revision })
# Will fail with PgEventstore::WrongExpectedRevisionError error, because stream version is 1 now, but :expected_revision 
# option is 0
PgEventstore.client.append_to_stream(stream, event2, options: { expected_revision: revision })
```

### Dynamic Consistency Boundaries support

You can validate a revision of separate event type(s) when publishing an event. This allows you to enforce consistency
of a specific event type(s) instead the consistency of the whole stream. To do so, you have to supply a
<event type>-to-<event revision> map as a value of `:expected_revion` option. Available per-type expected revisions:

- `:any`. Doesn't perform any checks. This is the default.
- `:no_event`. Expects an event to be absent when appending an event
- `:event_exists`. Expects an event to be present when appending an event
- a revision number(Integer). Expects an event to be in the given revision.

For example, next append command succeeds only if there is no `Foo` event, `Bar` event has revision `1` and `Baz` event
exists with any revision:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
event = PgEventstore::Event.new(data: { foo: :bar })
PgEventstore.client.append_to_stream(
  stream, event, options: { expected_revision: { 'Foo' => :no_event, 'Bar' => 1, 'Baz' => :event_exists } }
)
```

If event type(s) revision validation fails - `PgEventstore::WrongExpectedTypesRevisionError` exception is risen. Please
note, that this is different exception class comparing to the one which is present when stream revision validation
fails(`PgEventstore::WrongExpectedRevisionError`).

## Event markers

You can assign multiple markers(strings) to an event. This is multipurpose feature which may have application-specific
meaning, like observability or can be used as an additional constraint to validate event type revision as a part of
Dynamic Consistency Boundaries support.

### Publishing event with markers

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
event = PgEventstore::Event.new(markers: %w[foo bar])
PgEventstore.client.append_to_stream(stream, event)
```

Refer to [Read API docs](reading_events.md#filtering-events-by-markers) to find out how to filter events using markers.

### Dynamic Consistency Boundaries and markers

In addition to [per-event type validation](appending_events.md#dynamic-consistency-boundaries-support) - you can specify
a set of markers the specific event type may contain in order to pass revision validation. The available per-type
revisions are the same(`:any`, `:no_event`, `:event_exists` or number), but the syntax is a bit different. The example
bellow succeeds if there is no `Foo` event yet with either `'foo'` **or** `'bar'` marker:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
event = PgEventstore::Event.new(type: 'Foo', markers: ['bar'])
PgEventstore.client.append_to_stream(
  stream, event, options: { expected_revision: { 'Foo' => { expected_revision: :no_event, markers: %w[foo bar] } } }
)
```

Please note, there is no possibility to ensure the event has both - `'foo'` and `'bar'` markers. If you want to build
the logic that requires to differentiate between events with `'foo'`, `'bar'` and both markers - you have to
additionally mark such events with third marker. For example, you can have `'foobar'` marker which is used for events
with both `'foo'` and `'bar'` markers:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
event = PgEventstore::Event.new(type: 'Foo', markers: %w[foo bar foobar])
PgEventstore.client.append_to_stream(
  stream, event, options: { expected_revision: { 'Foo' => { expected_revision: :no_event, markers: %w[foobar] } } }
)
```

### Observability and markers

It is worth to explicitly mention this use case of markers as it is very desirable behavior when it comes to event
store. Let's describe simple approval-based user creation flow. Let's say each application layer produce each event from
the list bellow, based on the decisions of previous layer:
- UserRegistrationRequested
- UserCreationApproved
- UserCreated

We end up having three events in our event store. By looking at those events it would be hard to answer the question -
what was the cause of each of them? The answer to this question is critical in understanding actions and their
consequences in Event Sourced applications.

How markers can be helpful here? For example, we can use `Event#id` as a marker to build a chain of related events
across application layers:

```ruby
require 'securerandom'

OBSERVABILITY_PREFIX = 'O:'
OBSERVABILITY_PARENT_PREFIX = 'Op:'

# Layer 1
stream = PgEventstore::Stream.new(context: 'User', stream_name: 'RegistrationRequest', stream_id: '1')
id = SecureRandom.uuid_v7
registration_request = PgEventstore::Event.new(
  type: 'UserRegistrationRequested', id:, markers: ["#{OBSERVABILITY_PREFIX}#{id}"]
)
PgEventstore.client.append_to_stream(stream, registration_request)

# Layer 2
registration_request_id = PgEventstore.client.read(
  PgEventstore::Stream.new(context: 'User', stream_name: 'RegistrationRequest', stream_id: '1'),
  options: { filter: { event_types: ['UserRegistrationRequested'] }, direction: :desc, max_count: 1 }
).first.id

id = SecureRandom.uuid_v7
stream = PgEventstore::Stream.new(context: 'User', stream_name: 'RegistrationApproval', stream_id: '1')
creation_approved = PgEventstore::Event.new(
  id:,
  type: 'UserCreationApproved',
  markers: ["#{OBSERVABILITY_PREFIX}#{id}", "#{OBSERVABILITY_PARENT_PREFIX}#{registration_request_id}"]
)
PgEventstore.client.append_to_stream(stream, creation_approved)

# Layer 3
creation_approved_id = PgEventstore.client.read(
  PgEventstore::Stream.new(context: 'User', stream_name: 'RegistrationApproval', stream_id: '1'),
  options: { filter: { event_types: ['UserCreationApproved'] }, direction: :desc, max_count: 1 }
).first.id
id = SecureRandom.uuid_v7
stream = PgEventstore::Stream.new(context: 'User', stream_name: 'User', stream_id: '1')
user_created = PgEventstore::Event.new(
  id:,
  type: 'UserCreated',
  markers: ["#{OBSERVABILITY_PREFIX}#{id}", "#{OBSERVABILITY_PARENT_PREFIX}#{creation_approved_id}"]
)
PgEventstore.client.append_to_stream(stream, user_created)
```

Now you can go to admin web UI and navigate through markers of each event to inspect dependencies. You can also build a
dependency graph and visualize it somehow, but the implementation of such functional is out of scope of this
documentation.

## What to do when a WrongExpectedRevisionError or WrongExpectedTypesRevisionError error is risen?

Imagine the following scenario:

1. You load events of a stream to build the state of your business object represented by the stream.
2. You check your business rules to see if you can change that object's state the way you want to change it.
3. If no business rules have been violated, you have the go to publish the event representing the state change.
4. To make sure the new event will follow the last event you used to build your object state, you retrieve that last
   event's revision and increase it by one. You now have the expected revision for the event to be published.
5. You publish the event but retrieve a `WrongExpectedRevisionError`. This means another process has appended an event
   to the same stream, after you were loading your business object, while you were checking your business rules.
6. Now you need to repeat the process: load your business objects from the updated events stream, apply your business
   rules and if there is still no violation, try to append the event with the updated stream revision. You can do this
   procedure until the event is published or a maximum number of retries has been reached.

The following example shows the described retry procedure, with a simple business rule that does not allow adding an
event after a `UserRemoved` event:

```ruby
class UserAboutMeChanged < PgEventstore::Event
end

class UserRemoved < PgEventstore::Event
end

def latest_event(stream)
  PgEventstore.client.read(stream, options: { max_count: 1, direction: 'Backwards' }).first
rescue PgEventstore::StreamNotFoundError
end

def publish_event(stream, event)
  retries_count = 0
  begin
    last_event = latest_event(stream)
    # Ensure that the last event is not 'UserRemoved' event
    return if last_event&.type == 'UserRemoved'

    PgEventstore.client.append_to_stream(stream, event, options: { expected_revision: last_event&.stream_revision })
  rescue PgEventstore::WrongExpectedRevisionError => e
    # Parallel process has appended another event after we read the latest event, but before we appended our event. Such
    # scenarios can be safely retried.
    retries_count += 1
    raise if retries_count > 3
    retry
  end
end

stream = PgEventstore::Stream.new(context: 'UserProfile', stream_name: 'User', stream_id: '1')
event = UserAboutMeChanged.new(data: { user_id: '123', about_me: 'hi there!' })

publish_event(stream, event)
```

## Middlewares

If you would like to skip some of your registered middlewares from processing events before they get appended to a
stream - you should use the `:middlewares` argument which allows you to override the list of middlewares you would like
to use.

Let's say you have these registered middlewares:

```ruby
PgEventstore.configure do |config|
  config.middlewares = { foo: FooMiddleware.new, bar: BarMiddleware.new, baz: BazMiddleware.new }
end
```

And you want to skip `FooMiddleware` and `BazMiddleware`. You simply have to provide an array of corresponding
middleware keys you would like to use:

```ruby
event = PgEventstore::Event.new
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.append_to_stream(stream, event, middlewares: %i[bar])
```

See [Writing middleware](writing_middleware.md) chapter for info about what is middleware and how to implement it.
