# frozen_string_literal: true

module PgEventstore
  class EventSerializer
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
      event
    end

    # @return [PgEventstore::EventSerializer]
    def without_middlewares
      self.class.new([])
    end
  end
end
