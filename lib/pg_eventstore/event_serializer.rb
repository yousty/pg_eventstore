# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventSerializer
    # @!attribute middlewares
    #   @return [Array<#deserialize, #serialize>]
    attr_reader :middlewares

    # @param middlewares [Array<#deserialize, #serialize>]
    def initialize(middlewares)
      @middlewares = middlewares
    end

    # @param event [PgEventstore::Event]
    # @return [PgEventstore::Event]
    def serialize(event)
      @middlewares.each do |middleware|
        middleware.serialize(event)
      end
      event.markers.uniq!
      if event.markers.any?
        event.metadata[Event::MARKERS_METADATA_KEY] = event.markers
      else
        event.metadata.delete(Event::MARKERS_METADATA_KEY)
      end
      event
    end

    # @return [PgEventstore::EventSerializer]
    def without_middlewares
      self.class.new([])
    end
  end
end
