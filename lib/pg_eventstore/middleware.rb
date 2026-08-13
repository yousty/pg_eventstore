# frozen_string_literal: true

module PgEventstore
  module Middleware
    # @param event [PgEventstore::Event]
    # @return [void]
    def serialize(event)
    end

    # @param event [PgEventstore::Event]
    # @return [void]
    def deserialize(event)
    end

    # Whether #deserialize should be applied to the events which are echoed back by
    # PgEventstore::Client#append_to_stream and PgEventstore::Client#link_to. Override it and return +false+ to skip the
    # deserialization of the appended events. Useful when #deserialize is expensive and its result is not needed on the
    # write path. Reading events is not affected by this setting.
    # @return [Boolean]
    def deserialize_on_append?
      true
    end
  end
end
