# Reading Events

## Reading from a specific stream

The easiest way to read a stream forwards is to supply a `PgEventstore::Stream` object.

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.read(stream)
# => [#<PgEventstore::Event 0x1>, #<PgEventstore::Event 0x1>, ...]
```

### max_count

You can provide the `:max_count` option. This option determines how many records to return in a response. Default is
`1000` and it can be changed with the `:max_count` configuration setting (see [**"Configuration"**](configuration.md)
chapter):

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.read(stream, options: { max_count: 100 })
```

### resolve_link_tos

When reading streams with projected events (links to other events) you can chose to resolve those links by setting
`resolve_link_tos` to `true`, returning the original event instead of the "link" event.

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.read(stream, options: { resolve_link_tos: true })
```

### from_revision

You can define from which revision number you would like to start to read events:

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.read(stream, options: { from_revision: 2 })
```

### direction

As well as being able to read a stream forwards you can also go backwards. This can be achieved by providing the
`:direction` option:

```ruby
stream = PgEventstore::Stream.new(context: 'MyAwesomeContext', stream_name: 'User', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.read(stream, options: { direction: 'Backwards' })
```

## Checking if stream exists

In case a stream with given name does not exist, a `PgEventstore::StreamNotFoundError` error will be raised:

```ruby
begin
  stream = PgEventstore::Stream.new(context: 'non-existing-context', stream_name: 'User', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
  PgEventstore.client.read(stream, options: { max_count: 1 })
rescue PgEventstore::StreamNotFoundError => e
  puts e.message # => Stream #<PgEventstore::Stream:0x01> does not exist.
  puts e.stream # => #<PgEventstore::Stream:0x01>
end
```

## Reading from the "all" stream

"all" stream definition means that you don't scope your events when reading them from the database. To get the "all"
`PgEventstore::Stream` instance you have to call the `all_stream` method:

```ruby
PgEventstore::Stream.all_stream
```

Now you can use it to read from the "all" stream:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream)
```

You can read from a specific position of the "all" stream. This is very similar to reading from a specific revision of a
specific stream, but instead of the `:from_revision` option you have to provide the `:from_position` option:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { from_position: 9023, direction: 'Backwards' })
```

## Middlewares

If you would like to skip some of your registered middlewares from processing events after they being read from a
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
PgEventstore.client.read(PgEventstore::Stream.all_stream, middlewares: %i[bar])
```

See [Writing middleware](writing_middleware.md) chapter for info about what is middleware and how to implement it.

## Filtering

When reading events, you can additionally filter the result. Available attributes for filtering depend on the type of
stream you are reading from. Reading from the "all" stream supports filters by stream attributes, event types and event
markers. Reading from a specific stream supports filters by event types and event markers only.

### Specific stream filtering

#### Filtering events by their types

Read `Foo` and `Bar` events from the given stream:
```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.read(stream, options: { filter: { event_types: %w[Foo Bar] } })
```

Also, you can provide event type values using `{ type: 'MyType' }` syntax. Example:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.read(stream, options: { filter: { event_types: [{ type: 'Foo' }, { type: 'Bar' }] } })
```

#### Filtering events by markers

Read events, marked as either `'foo'` **or** `'bar'`:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.read(stream, options: { filter: { event_types: [{ markers: %w[foo bar] }] } })
```

##### Limitations

Please note - there is no functional to filter events that are marked with both `'foo'` **and** `'bar'` markers. If you
need a combination of both - you have to create another event marker - for example `'foobar'` - and additionally mark
events using it that have both - `'foo'` and `'bar'` markers. Example:

```ruby
event1 = PgEventstore::Event.new(markers: ['foo'])
event2 = PgEventstore::Event.new(markers: ['bar'])
event3 = PgEventstore::Event.new(markers: %w[foo bar foobar])
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '3')
PgEventstore.client.append_to_stream(stream, [event1, event2, event3])
# Returns all three events
PgEventstore.client.read(stream, options: { filter: { event_types: [{ markers: %w[foo bar] }] } })
# Returns only the third event
PgEventstore.client.read(stream, options: { filter: { event_types: [{ markers: ['foobar'] }] } })
```

#### Filtering events by event types with markers

You can provide per event type markers list. The effect of this is that each event type is additionally restricted with
the set of markers. In next example events with `'Foo'` type is only returned when they are additionally marked with
`'foo'` or `'bar'` markers:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.read(stream, options: { filter: { event_types: [{ type: 'Foo', markers: %w[foo bar] }] } })
```

You can also combine event types filter, event type with markers filter and markers filter. Next query returns all
events that are either:
- marked with `'baz'`
- or have type `'Foo'` that are marked with either `'foo'` or `'bar'`
- or have type `'Bar'`
```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.read(
  stream,
  options: {
    filter: {
      event_types: [
        { markers: ['baz'] },
        { type: 'Foo', markers: %w[foo bar] },
        { type: 'Bar' }
      ]
    }
  }
)
```

### "all" stream filtering

#### Limitations

There is a limitation on a set of stream attributes that can be used when filtering an "all" stream result.
Available combinations:

- `:context`
- `:context` and `:stream_name`
- `:context`, `:stream_name` and `:stream_id`

So this is not allowed(filter is simply ignored):

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ stream_name: 'FooCtx' }] } }
) # => Array of events like if there is no filter at all
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ stream_name: 'FooCtx', stream_id: '1' }] } }
) # => Array of events like if there is no filter at all
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ stream_id: '1' }] } }
) # => Array of events like if there is no filter at all
```

but this is allowed:

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx' }] } }
)
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx', stream_name: 'Foo' }] } }
)
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx', stream_name: 'Foo', stream_id: '1' }] } }
)
```

Also, you can't filter by markers only without a specific event type with only `:context` or `:context` and
`:stream_name`. So, this is not allowed:

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx' }], event_types: [{ markers: ['foo'] }] } }
) # => exception
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx', stream_name: 'Foo' }], event_types: [{ markers: ['foo'] }] } }
) # => exception
```

but this is allowed:

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx' }], event_types: [{ markers: ['foo'], type: 'Foo' }] } }
) # => Array of events
```

#### Filtering events by type and/or markers

Please refer to the documentation of [Specific stream filtering](reading_events.md#reading-from-a-specific-stream) for
more examples how to filter by event types and/or markers. The only thing which changes is stream argument. To filter
"all" stream - you have to provide `PgEventstore::Stream.all_stream` instead of specific stream. Example:

```ruby
PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { event_types: %w[Foo Bar] } })
```

#### Filtering events by context

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'MyAwesomeContext' }] } }
)
```

#### Filtering events by context and name

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'MyAwesomeContext', stream_name: 'User' }] } }
)
```

#### Filtering events by stream context, stream name and stream id

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: {
    filter: {
      streams: [{ context: 'MyAwesomeContext', stream_name: 'User', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae' }]
    }
  }
)
```

You can provide several sets of stream's attributes. The result will be a union of events that match those criteria. For
example, next query will return all events that belong to streams with `AnotherContext` context and all events that
belong to streams with `MyAwesomeContext` context and `User` stream name:

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: {
    filter: {
      streams: [{ context: 'AnotherContext' }, { context: 'MyAwesomeContext', stream_name: 'User' }] 
    }
  }
)
```

#### Filtering events by stream attributes, event types and/or markers

Please refer to the documentation of [Specific stream filtering](reading_events.md#reading-from-a-specific-stream) for
more examples how to filter by event types and/or markers.

You can also mix filtering by stream attributes, event types and markers. The result is union of combinations of 
each stream filter and event types filter. For example, next query returns events with type either `Foo`, marked
by `'foo'` marker, or `Bar` and belong to streams from `FooCtx` or `BarCtx` contexts:

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream,
  options: {
    filter: {
      streams: [{ context: 'FooCtx' }, { context: 'BarCtx' }],
      event_types: [{ type: 'Foo', markers: ['foo'] }, { type: 'Bar' }]
    }
  }
)
```

## Pagination

You can use `#read_paginated` to iterate over all (filtered) events. It yields each batch of records that was found
according to the filter options:

```ruby
# Read from the specific stream
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.read_paginated(stream).each do |events|
  events.each do |event|
    # iterate through events
  end
end

# Read from "all" stream
PgEventstore.client.read_paginated(PgEventstore::Stream.all_stream).each do |events|
  events.each do |event|
    # iterate through events
  end
end
```

Options are the same as for `#read` method. Several examples:

```ruby
# Read "Foo" events only from the specific stream
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
PgEventstore.client.read_paginated(stream, options: { filter: { event_types: ['Foo'] } }).each do |events|
  events.each do |event|
    # iterate through events
  end
end

# Backwards read from "all" stream
PgEventstore.client.read_paginated(PgEventstore::Stream.all_stream, options: { direction: 'Backwards' }).each do |events|
  events.each do |event|
    # iterate through events
  end
end

# Set batch size to 100
PgEventstore.client.read_paginated(PgEventstore::Stream.all_stream, options: { max_count: 100 }).each do |events|
  events.each do |event|
    # iterate through events
  end
end

# Reading from projection stream
projection_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'FooProjection', stream_id: '1')
PgEventstore.client.read_paginated(projection_stream, options: { resolve_link_tos: true }).each do |events|
  events.each do |event|
    # iterate through events
  end
end
```

## Grouping events by type

`pg_eventstore` implements an ability to group events by type when reading from a stream. Example:

```ruby
stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
event1 = PgEventstore::Event.new(type: 'Foo', data: { foo: 1 })
event2 = PgEventstore::Event.new(type: 'Foo', data: { foo: 2 })
event3 = PgEventstore::Event.new(type: 'Bar', data: { bar: 2 })

PgEventstore.client.append_to_stream(stream, [event1, event2, event3])

PgEventstore.client.read_grouped(stream) # => returns event1 and event3
```

API is very similar to the API of `#read`, but it ignores `:max_count` options as the result is always returns a set of
event types in your stream.

Reading most recent events:

```ruby
PgEventstore.client.read_grouped(stream, options: { direction: :desc })
```

Filtering the result by stream attributes:

```ruby
PgEventstore.client.read_grouped(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx' }] } }
)
```

Filtering the result by event types:

```ruby
PgEventstore.client.read_grouped(
  PgEventstore::Stream.all_stream,
  options: { filter: { event_types: ['Foo', 'Bar'] } }
)
```

Filtering by stream attributes and event types:

```ruby
PgEventstore.client.read_grouped(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx' }], event_types: ['Foo', 'Bar'] } }
)
```

Reading most recent events until the certain stream revision:

```ruby
PgEventstore.client.read_grouped(stream, options: { direction: :desc, from_revision: 1 })
```

Reading the oldest events from the certain stream revision:

```ruby
PgEventstore.client.read_grouped(stream, options: { direction: :asc, from_revision: 1 })
```

Reading most recent events until the certain global position:

```ruby
PgEventstore.client.read_grouped(PgEventstore::Stream.all_stream, options: { direction: :desc, from_position: 5 })
```

Reading the oldest events from the certain global position:

```ruby
PgEventstore.client.read_grouped(PgEventstore::Stream.all_stream, options: { direction: :asc, from_position: 5 })
```

### Event types list lookup

If you do not provide event types filter - event types list will be determined based on the rest of arguments(a stream
argument or a stream filters option).

### Multiple events of same type in the result

If same event type appear in different streams(different by `#context` and `#stream_name`) - those events will appear in
the result. This is because even though `Event#type` value may be the same - its meaning may have different meaning in
different `context`/`stream_name` couple. Example:

```ruby
stream1 = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
stream2 = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1')

event1 = PgEventstore::Event.new(type: 'Foo', data: { foo: 1 })
event2 = PgEventstore::Event.new(type: 'Foo', data: { foo: 2 })

PgEventstore.client.append_to_stream(stream1, event1)
PgEventstore.client.append_to_stream(stream2, event2)

PgEventstore.client.read_grouped(
  PgEventstore::Stream.all_stream,
  options: { filter: { streams: [{ context: 'FooCtx' }] } }
) # => returns both events even though they are of "Foo" type
```
