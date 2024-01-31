# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventDeserializer
    attr_reader :middlewares, :event_class_resolver

    # @param middlewares [Array<Object<#deserialize, #serialize>>]
    # @param event_class_resolver [#call]
    def initialize(middlewares, event_class_resolver)
      @middlewares = middlewares
      @event_class_resolver = event_class_resolver
    end

    # @param raw_events [Array<Hash>]
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
      event.stream = PgEventstore::Stream.new(**attrs['stream'].transform_keys(&:to_sym)) if attrs.key?('stream')
      event
    end

    # @return [PgEventstore::EventDeserializer]
    def without_middlewares
      self.class.new([], event_class_resolver)
    end
  end
end
