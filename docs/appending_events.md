# Appending Events

## Append your first event

The easiest way to append an event is to create an event object and a stream object and call the client's `#append_to_stream` method.

```ruby
require 'securerandom'

class SomethingHappened < PgEventstore::Event
end

event = SomethingHappened.new(data: { user_id: SecureRandom.uuid, title: "Something happened" })
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.append_to_stream(stream, event)
# => #<SomethingHappened:0x0 @context="MyAwesomeContext", @created_at=2023-11-30 14:47:31.296229 UTC, @data={"title"=>"Something happened", "user_id"=>"be52a81c-ad5b-4cfd-a039-0b7276974e6b"}, @global_position=7, @id="0b01137b-bdd8-4f0d-8ccf-f8c959e3a324", @link_id=nil, @metadata={}, @stream_id="f37b82f2-4152-424d-ab6b-0cc6f0a53aae", @stream_name="SomeStream", @stream_revision=0, @type="SomethingHappened">
```

## Appending multiple events

You can pass an array of events to the `#append_to_stream` method. This way events will be appended one-by-one. **This operation is atomic and it guarantees that events are added to the stream in the given order.**

```ruby
require 'securerandom'

class SomethingHappened < PgEventstore::Event
end

event1 = SomethingHappened.new(data: { user_id: SecureRandom.uuid, title: "Something happened 1" })
event2 = SomethingHappened.new(data: { user_id: SecureRandom.uuid, title: "Something happened 2" })
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.append_to_stream(stream, [event1, event2])
```

### Duplicated event id

If two events with the same id are appended to any stream - `pg_eventstore` will only append one event, and the second command will raise an error.

```ruby
class SomethingHappened < PgEventstore::Event
end

event = SomethingHappened.new(id: SecureRandom.uuid)
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.append_to_stream(stream, event)
# Raises PG::UniqueViolation error
PgEventstore.client.append_to_stream(stream, event)
```

## Handling concurrency

When appending events to a stream you can supply a stream state or stream revision. You can use this to tell `pg_eventstore` what state or version you expect the stream to be in when you append. If the stream isn't in that state then an exception will be thrown.

For example if we try to append two records expecting both times that the stream doesn't exist we will get an exception on the second:

```ruby
require 'securerandom'

class SomethingHappened < PgEventstore::Event
end

event1 = SomethingHappened.new(data: { foo: :bar })
event2 = SomethingHappened.new(data: { bar: :baz })
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: SecureRandom.uuid)

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

This check can be used to implement optimistic concurrency. When you retrieve a stream, you take note of the current version number, then when you save it back you can determine if somebody else has modified the record in the meantime.

```ruby
require 'securerandom'

class SomethingHappened < PgEventstore::Event
end

stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: SecureRandom.uuid)
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

### What to do when a PgEventstore::WrongExpectedRevisionError error is risen?

Imagine the following scenario:
1. You load events of a stream to build the state of your business object represented by the stream.
2. You check your business rules to see if you can change that object's state the way you want to change it.
3. If no business rules have been violated, you have the go to publish the event representing the state change.
4. To make sure the new event will follow the last event you used to build your object state, you retrieve that last event's revision and increase it by one. You now have the expected revision for the event to be published.
5. You publish the event but retrieve a `WrongExpectedRevisionError`. This means another process has appended an event to the same stream, after you were loading your business object, while you were checking your business rules.
6. Now you need to repeat the process: load your business objects from the updated events stream, apply your business rules and if there is still no violation, try to append the event with the updated stream revision. You can do this procedure until the event is published or a maximum number of retries has been reached.

The following example shows the described retry procedure, with a simple business rule that does not allow adding an event after a `UserRemoved` event:

```ruby
require 'securerandom'
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

stream = PgEventstore::Stream.new(context: 'UserProfile', stream_name: 'User', stream_id: SecureRandom.uuid)
event = UserAboutMeChanged.new(data: { user_id: '123', about_me: 'hi there!' })

publish_event(stream, event)
```

## Middlewares

If you would like to prevent your registered middlewares from processing events before they get appended to a stream - you should use the `:skip_middlewares` argument:

```ruby
event = PgEventstore::Event.new
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.append_to_stream(stream, event, skip_middlewares: true)
```

See [Writing middleware](writing_middleware.md) chapter for info about what is middleware and how to implement it.
