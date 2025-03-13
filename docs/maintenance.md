# Maintenance

`pg_eventstore` provides maintenance functional which can be used to clean up various objects in your database.

## Delete a stream

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1')
PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
PgEventstore.maintenance.delete_stream(stream) # => true
```
deletes all events in the given stream. If the given stream does not exist - `false` is returned: 

```ruby
stream = PgEventstore::Stream.new(context: 'NonExistingCtx', stream_name: 'NonExistingStream', stream_id: '1')
PgEventstore.maintenance.delete_stream(stream) # => false
```

**Please note that this operation does not automatically delete links to deleted events - you have to do delete them separately.**

## Delete an event

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1')
PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
# Grab the first event for further deletion
event = PgEventstore.client.read(stream, options: { max_count: 1 }).first
PgEventstore.maintenance.delete_event(event) # => true
```
deletes the given event. If the given event does not exist - `false` is returned:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1')
PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
# Grab the first event for further deletion
event = PgEventstore.client.read(stream, options: { max_count: 1 }).first
PgEventstore.maintenance.delete_event(event) # => true
PgEventstore.maintenance.delete_event(event) # => false
```

**Please note that this operation does not automatically delete links to the deleted event - you have to do delete them separately.**

### Deleting an event in a large stream

There can be a situation when you would like to delete an event in a large stream. If an event is in the position where there are 1000+ events after it in a stream - a `PgEventstore::TooManyRecordsToLockError` error will be raised. This is because in addition to removing the event, we need to adjust the rest of the stream by updating the `#stream_revision` of all events that come after this event. To overcome this limitation - you can provide `force: true` flag:

```ruby
PgEventstore.maintenance.delete_event(event, force: true)
```

Because the update operation can lock thousands of events - `#delete_event` can be slow and can slow down other processes which insert events in the same stream at the same moment. **Thus, it is recommended to avoid using `#delete_event` in your business logic.**
