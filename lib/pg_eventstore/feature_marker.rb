# frozen_string_literal: true

module PgEventstore
  class FeatureMarker
    include Extensions::OptionsExtension
    include Extensions::OptionsDefaults

    # @!attribute marker
    #   @return [String]
    attribute(:marker)
    # @!attribute description
    #   @return [String, nil] the description of the maker. Can be used as human-friendly explanation of the purpose
    attribute(:description)
    # @!attribute purpose
    #   @return [Symbol, nil] the purpose of the maker. Can be used as an identifier in your implementation
    attribute(:purpose)
  end
end
