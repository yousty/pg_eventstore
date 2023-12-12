# Writing middleware

Middlewares are objects that modify events before they are appended to a stream, or right after they are read from a stream. Middleware object must respond to `#serialize` and `#deserialize` methods. The `#serialize` method is called each time an event is going to be appended. The `#deserialize` method is called each time an event is read from a stream. There are two ways how you can define a middleware:

- by defining your class and including `PgEventstore::Middleware` module in it. This way you can override only one of its methods, or both of them. Example:

```ruby
# Override #serialize only to define your custom logic
class MyAwesomeSerializer
  include PgEventstore::Middleware

  def serialize(event)
    do_something
  end
end

# Override #deserialize only to define your custom logic
class MyAwesomeDeserializer
  include PgEventstore::Middleware

  def deserialize(event)
    do_something
  end
end

# Override both #serialize and #deserialize methods
class MyAwesomeMiddleware
  include PgEventstore::Middleware

  def serialize(event)
    do_something
  end

  def deserialize(event)
    do_something
  end
end

# Configure your middlewares
PgEventstore.configure do |config|
  config.middlewares = { my_awesome_serializer: MyAwesomeSerializer.new, my_awesome_deserializer: MyAwesomeDeserializer.new, my_awesome_middleware: MyAwesomeMiddleware.new }
end
```

- implement your own object that implements `#serialize` and `#deserialize` methods. Example: 

```ruby
require 'securerandom'

# Provide some basic functionality for large payload extraction implementations. Every event in your app will be inherited from this class.
class MyAppAbstractEvent < PgEventstore::Event
  def self.payload_store_fields
    []
  end

  def fields_with_large_payloads
    data.slice(*self.class.payload_store_fields)
  end
end

class DescriptionChangedEvent < MyAppAbstractEvent
  def self.payload_store_fields
    %w[description]
  end
end

class ExtractLargePayload
  class << self
    def serialize(event)
      return if event.fields_with_large_payloads.empty?

      event.fields_with_large_payloads.each do |field, value|
        # Extract fields with large payload asynchronously.
        event.data[field] = extract_large_payload_async(field, value)
      end
    end

    def deserialize(event)
      # Load real values for large payload fields. You can use self.class.payload_store_fields here, but then you would require
      # the event definition in each mircoservice you load this event
      event.data.select { |k, v| v.start_with?('large-payload:') }.each do |field, value|
        event.data[field] = resolve_large_payload(value.delete('large-payload:'))
      end
    end

    private

    def extract_large_payload_async(field_name, value)
      payload_key = "large-payload:#{field_name}-#{Digest::MD5.hexdigest(value)}"
      Thread.new do
        Faraday.post(
          "https://my.awesome.api/api/extract_large_payload",
          { payload_key: payload_key, value: value }
        )
      end
      payload_key
    end

    def resolve_large_payload(payload_key)
      JSON.parse(Faraday.get("https://my.awesome.api/api/large_payload", { payload_key: payload_key }).body)['value']
    end
  end  
end

# Configure our middlewares
PgEventstore.configure do |config|
  config.middlewares = { extract_large_payload: ExtractLargePayload }
end
```

Now you can use it as follows:

```ruby
event = DescriptionChangedEvent.new(data: { 'description' => 'some description' })
stream = PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-stream', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.append_to_stream(stream, event)
# => #<DescriptionChangedEvent:0x0 @data={"description"=>"large-payload:description-7815696ecbf1c96e6894b779456d330e"}, ...>
```

But when you read it next time, it will automatically resolve the `description` value:

```ruby
stream = PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-stream', stream_id: 'f37b82f2-4152-424d-ab6b-0cc6f0a53aae')
PgEventstore.client.read(stream).last
# => #<DescriptionChangedEvent:0x0 @data={"description"=>"some description"}, ...>
```

## Remarks

It is important to know that `pg_eventstore` may retry commands. In that case `#serialize` and `#deserialize` methods may also be retried. You have to make sure that the implementation of `#serialize` and `#deserialize` always returns the same result for the same input, and it does not create duplications. Let's look at the `#serialize` implementation from the example above:

```ruby
def serialize(event)
  return if event.fields_with_large_payloads.empty?

  event.fields_with_large_payloads.each do |field, value|
    # Extract fields with large payload asynchronously.
    event.data[field] = extract_large_payload_async(field, value)
  end
end

private

def extract_large_payload_async(field_name, value)
  payload_key = "large-payload:#{field_name}-#{Digest::MD5.hexdigest(value)}"
  Thread.new do
    Faraday.post(
      "https://my.awesome.api/api/extract_large_payload",
      { payload_key: payload_key, value: value }
    )
  end
  payload_key
end
```

Private method `#extract_large_payload_async` should return the same result when passing the same `field_name` and `value` arguments values, and `POST https://my.awesome.api/api/extract_large_payload` may not want to produce duplicates when called multiple times with the same payload.

## Async vs Sync implementation

You may notice that the extracting of a large payload is asynchronous in the example above. It is recommended approach of the implementation of `#serialize` method to increase overall performance. But if it hard for you to guarantee the persistence of a payload value - you can go with sync approach, thus not allowing event to be persisted if a payload extraction request fails.
