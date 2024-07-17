# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventDeserializer
    # @!attribute middlewares
    #   @return [Array<#deserialize, #serialize>]
    attr_reader :middlewares
    # @!attribute event_class_resolver
    #   @return [#call]
    attr_reader :event_class_resolver

    # @param middlewares [Array<Object<#deserialize, #serialize>>]
    # @param event_class_resolver [#call]
    def initialize(middlewares, event_class_resolver)
      @middlewares = middlewares
      @event_class_resolver = event_class_resolver
    end

    # @param raw_events [Array<Hash>]
    # @return [Array<PgEventstore::Event>]
    def deserialize_many(raw_events)
      raw_events.map(&method(:deserialize))
    end

    # @param attrs [Hash]
    # @return [PgEventstore::Event]
    def deserialize(attrs)
      event = event_class_resolver.call(attrs['type']).new(**attrs.transform_keys(&:to_sym))
      middlewares.each do |middleware|
        middleware.deserialize(event)
      end
      event.stream = PgEventstore::Stream.new(
        **attrs.slice('context', 'stream_name', 'stream_id').transform_keys(&:to_sym)
      )
      event.link = without_middlewares.deserialize(attrs['link']) if attrs.key?('link')
      event
    end

    # @return [PgEventstore::EventDeserializer]
    def without_middlewares
      self.class.new([], event_class_resolver)
    end
  end
end
