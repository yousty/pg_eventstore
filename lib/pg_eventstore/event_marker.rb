# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventMarker
    include Extensions::OptionsExtension
    include Extensions::OptionsDefaults

    # @!attribute id
    #   @return [Integer]
    attribute(:id)
    # @!attribute name
    #   @return [String]
    attribute(:name)
  end
end
