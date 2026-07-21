# Reading streams

`pg_eventstore` provides API to directly read a set of streams and detailed information of them.

## Stream revision

`Client#stream_revision` provides the best speed of retrieving current stream revision. Alternative way would be to read
last event in the stream, but it is much slower than this and may raise exception if stream does not exist. Example:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.stream_revision(stream) 
# => stream revision or Stream::NON_EXISTING_STREAM_REVISION (which is -1) if stream does not exist
```

## Streams list

You can directly retrieve a list of streams using `#read_streams`. The list is ordered by the stream starting position.
Starting position is a global position of the first event in the stream. Supported options are:

- `:direction`. Read direction. Default is `:asc`
- `:from_position`. Starting position to read from
- `:max_count`. Max number of objects to return

Examples:

```ruby
PgEventstore.client.read_streams
PgEventstore.client.read_streams(options: { direction: :desc })
PgEventstore.client.read_streams(options: { max_count: 10 })
PgEventstore.client.read_streams(options: { from_position: 123 })
PgEventstore.client.read_streams(options: { from_position: 123, direction: :desc })
PgEventstore.client.read_streams(options: { from_position: 123, max_count: 123 })
PgEventstore.client.read_streams(options: { from_position: 123, direction: :desc, max_count: 10 })
```

Unlike `Stream` object you can access via `Event#stream` of a persisted event - `Stream` objects from this API
additionally load values of `#starting_position` and `#stream_revision` attributes.

You can also paginate by streams. `#read_streams_paginated` yields an array of streams on each iteration. It accepts the
same list of options as `#read_streams`. Example:

```ruby
PgEventstore.client.read_streams_paginated(options: { max_count: 10 }).each do |streams|
  # yields up to :max_count objects
  streams.each do |stream|
    # do something with your stream
  end
end
```
