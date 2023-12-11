# Reading Events

## Reading from a specific stream

The easiest way to read a stream forwards is to supply a `PgEventstore::Stream` object.

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: '1')
PgEventstore.client.read(stream)
# => [#<PgEventstore::Event 0x1>, #<PgEventstore::Event 0x1>, ...]
```

### max_count

You can provide the `:max_count` option. This option determines how many records to return in a response. Default is `1000` and it can be changed with the `:max_count` configuration setting (see [**"Configuration"**](configuration.md) chapter):

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: '1')
PgEventstore.client.read(stream, options: { max_count: 100 })
```

### resolve_link_tos

When reading streams with projected events (links to other events) you can chose to resolve those links by setting `resolve_link_tos` to `true`, returning the original event instead of the "link" event.

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: '1')
PgEventstore.client.read(stream, options: { resolve_link_tos: true })
```

### from_revision

You can define from which revision number you would like to start to read events:

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: '1')
PgEventstore.client.read(stream, options: { from_revision: 2 })
```

### direction

As well as being able to read a stream forwards you can also go backwards. This can be achieved by providing the `:direction` option:

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: '1')
PgEventstore.client.read(stream, options: { direction: 'Backwards' })
```

## Checking if stream exists

In case a stream with given name does not exist, a `PgEventstore::StreamNotFoundError` error will be raised:

```ruby
begin
  stream = PgEventstore::Stream.new(context: 'non-existing-context', stream_name: 'User', stream_id: '1')
  PgEventstore.client.read(stream)
rescue PgEventstore::StreamNotFoundError => e
  puts e.message # => Stream #<PgEventstore::Stream:0x01> does not exist.
  puts e.stream # => #<PgEventstore::Stream:0x01>
end
```

## Reading from the "all" stream

"all" stream definition means that you don't scope your events when reading them from the database. To get the "all" `PgEventstore::Stream` instance you have to call the `all_stream` method: 

```ruby
PgEventstore::Stream.all_stream
```

Now you can use it to read from the "all" stream:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream)
```

You can read from a specific position of the "all" stream. This is very similar to reading from a specific revision of a specific stream, but instead of the `:from_revision` option you have to provide the `:from_position` option:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { from_position: 9023, direction: 'Backwards' })
```

## Middlewares

If you would like to prevent your registered middlewares from processing the read result - you should use the `:skip_middlewares` argument:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, skip_middlewares: true)
```

See [Writing middleware](writing_middleware.md) chapter for info about what is middleware and how to implement it.

## Filtering

When reading events, you can additionally filter the result. Available attributes for filtering depend on the type of stream you are reading from. Reading from the "all" stream supports filters by stream attributes and event types. Reading from a specific stream supports filters by event types only.  

### Specific stream filtering

Filtering events by their types:

```ruby
stream = PgEventstore::Stream.new(context: 'MYAwesomeContext', stream_name: 'User', stream_id: '1')
PgEventstore.client.read(stream, options: { filter: { event_types: %w[Foo Bar] } })
```

### "all" stream filtering

**Warning** There is a restriction on a set of stream attributes that can be used when filtering an "all" stream result. Available combinations:

- `:context`
- `:context` and `:stream_name`
- `:context`, `:stream_name` and `:stream_id`

All other combinations, like providing only `:stream_name` or providing `:context` with `:stream_id` will be ignored.


Filtering events by type:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { event_types: %w[Foo Bar] } })
```

Filtering events by context:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { streams: [{ context: 'MyAwesomeContext' }] } })
```

Filtering events by context and name:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { streams: [{ context: 'MYAwesomeContext', stream_name: 'User' }] } })
```

Filtering events by stream's context, stream's name and stream's id:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { streams: [{ context: 'MYAwesomeContext', stream_name: 'User', stream_id: '1' }] } })
```

You can provide several sets of stream's attributes. The result will be a union of events that match those criteria. For example, next query will return all events that belong to streams with `AnotherContext` context and all events that belong to streams with `MyAwesomeContext` context and `User` stream name:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { streams: [{ context: 'AnotherContext' }, { context: 'MyAwesomeContext', stream_name: 'User' }] } })
```

You can also mix filtering by stream's attributes and event types. The result will be intersection of events matching stream's attributes and event's types. For example, next query will return events which type is either `Foo` or `Bar` and which belong to a stream with `MyAwesomeContext` context:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { streams: [{ context: 'MyAwesomeContext' }], event_types: %w[Foo Bar] } })
```
