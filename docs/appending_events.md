# Appending Events

## Append your first event

The simplest way to append an event is to create an event object, a stream object and call client's `#append_to_stream` method.

```ruby
class SomethingHappened < PgEventstore::Event
end

event = SomethingHappened.new(data: { user_id: SecureRandom.uuid, title: "Something happened" })
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: '1')
PgEventstore.client.append_to_stream(stream, event)
# => #<SomethingHappened:0x0 @context="MyAwesomeContext", @created_at=2023-11-30 14:47:31.296229 UTC, @data={"title"=>"Something happened", "user_id"=>"be52a81c-ad5b-4cfd-a039-0b7276974e6b"}, @global_position=7, @id="0b01137b-bdd8-4f0d-8ccf-f8c959e3a324", @link_id=nil, @metadata={}, @stream_id="1", @stream_name="SomeStream", @stream_revision=0, @type="SomethingHappened">
```

## Appending multiple events

You can pass an array of events to the `#append_to_stream` method. This way events will be appended one-by-one. **This operation is atomic and it guarantees that events will go inside the stream in the same order they go in the given array.**

```ruby
class SomethingHappened < PgEventstore::Event
end

event1 = SomethingHappened.new(data: { user_id: SecureRandom.uuid, title: "Something happened 1" })
event2 = SomethingHappened.new(data: { user_id: SecureRandom.uuid, title: "Something happened 2" })
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: '1')
# First process
PgEventstore.client.append_to_stream(stream, [event1, event2])
# Second process
PgEventstore.client.append_to_stream(stream, event3)
```

### Duplicated event id

If two events with the same id are appended to any stream - `pg_eventstore` will only append one event, and second command will raise error.

```ruby
class SomethingHappened < PgEventstore::Event
end

event = SomethingHappened.new(id: SecureRandom.uuid)
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'SomeStream', stream_id: '1')
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

There are three available stream states:

- `:any`. Default behavior. 
- `:no_stream`. Expects a stream to be absent when appending an event
- `:stream_exists`. Expectes a stream to be present when appending an event

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

### What to do when PgEventstore::WrongExpectedRevisionError error raises?

What to do when an event has failed to be appended to a stream due to `WrongExpectedRevisionError` error? It depends on you business logic. For example, if you have a business rule that no events should be appended to a stream if it contains `Removed` event, you should provide `:expected_revision` option to ensure your stream is in the expected state and re-run your logic each time `WrongExpectedRevisionError` error raises:

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
