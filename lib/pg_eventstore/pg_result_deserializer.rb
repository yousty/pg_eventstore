# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class PgResultDeserializer
    attr_reader :middlewares, :event_class_resolver

    # @param middlewares [Array<Object<#deserialize, #serialize>>]
    # @param event_class_resolver [#call]
    def initialize(middlewares, event_class_resolver)
      @middlewares = middlewares
      @event_class_resolver = event_class_resolver
    end

    # @param pg_result [PG::Result]
    # @return [Array<PgEventstore::Event>]
    def deserialize(pg_result)
      pg_result.map(&method(:_deserialize))
    end
    alias deserialize_many deserialize

    # @param pg_result [PG::Result]
    # @return [PgEventstore::Event, nil]
    def deserialize_one(pg_result)
      return if pg_result.ntuples.zero?

      _deserialize(pg_result.first)
    end

    # @return [PgEventstore::PgResultDeserializer]
    def without_middlewares
      self.class.new([], event_class_resolver)
    end

    private

    # @param attrs [Hash]
    # @return [PgEventstore::Event]
    def _deserialize(attrs)
      event = event_class_resolver.call(attrs['type']).new(**attrs.transform_keys(&:to_sym))
      middlewares.each do |middleware|
        middleware.deserialize(event)
      end
      event.stream = PgEventstore::Stream.new(**attrs['stream'].transform_keys(&:to_sym)) if attrs.key?('stream')
      event
    end
  end
end
