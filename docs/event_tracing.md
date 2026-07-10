#  Event tracing

pg_eventstore implements event tracing feature out of the box via `PgEventstore::Middleware::EventTracing` middleware
class. It allows you to connect events between each other with markers and build causation dependency between them. The
middleware is not configured by default. You can configure it as follows:

```ruby
PgEventstore.configure do |config|
  config.middlewares = { event_tracing: PgEventstore::Middleware::EventTracing.new }
end
```

You can now supply new event with an event, based on which current event is going to be published. Example:

```ruby
stream = PgEventstore::Stream.new(context: 'User', stream_name: 'RegistrationRequest', stream_id: '1')
user_registration_confirmed = PgEventstore.client.append_to_stream(
  stream, PgEventstore::Event.new(type: 'UserRegistrationConfirmed')
)

stream = PgEventstore::Stream.new(context: 'User', stream_name: 'User', stream_id: '1')
user_created = PgEventstore.client.append_to_stream(
  stream, PgEventstore::Event.new(caused_by: user_registration_confirmed, type: 'UserCreated')
)
```

`UserCreated` event now has `#causation_id` value equal to `user_registration_confirmed.id`. Both of them have the same
`#correlation_id`. You can use those values to find those events.

Use `#correlation_id` to find all connected events:

```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream, 
  options: { filter: { event_types: [{ markers: [user_created.correlation_id] }] } }
) # => returns both events
```

Use `#causation_id` to find all events, which were persisted, based on the given causation id:
```ruby
PgEventstore.client.read(
  PgEventstore::Stream.all_stream, 
  options: { filter: { event_types: [{ markers: [user_registration_confirmed.id] }] } }
) # => returns both events
```

`#causation_id` and `#correlation_id` values are persisted into special keys of `#metadata` and are loaded back into 
`#causation_id` and `#correlation_id` attributes during the deserialization process. Related constants are:
- `PgEventstore::Middleware::EventTracing::CAUSATION_ID_KEY` for `#causation_id`
- `PgEventstore::Middleware::EventTracing::CORRELATION_ID_KEY` for `#correlation_id`

You can also find `#correlation_id` and `#causation_id` values in `Event#feature_markers` attribute, `Markers` section
of extended event view(it is available by clicking on `JSON` link with eye icon near it on the admin dashboard page)
under `Feature markers` chapter. It is only available when `PgEventstore::Middleware::EventTracing` is configured
though, but filtering by markers is always there despite on configuration options.
