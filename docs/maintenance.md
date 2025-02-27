# Maintenance

`pg_eventstore` provides maintenance functional which can be used to clean up various objects in the database.

## Delete a stream

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1')
PgEventstore.maintenance.delete_stream(stream)
```
deletes all events in the given stream. **Please note that this operation does not automatically delete links to those events - you have to do delete them separately.**
