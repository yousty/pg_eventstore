# frozen_string_literal: true

module PgEventstore
  class EventClassResolver
    # @param event_type [String, nil]
    # @return [Class]
    def call(event_type)
      Object.const_get(event_type)
    rescue NameError, TypeError
      PgEventstore.logger&.debug(<<~TEXT.strip)
        Unable to resolve class by `#{event_type}' event type. \
        Picking #{Event} event class to instantiate the event.
      TEXT
      Event
    end
  end
end
