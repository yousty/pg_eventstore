# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class StreamGlobalIndex
    include Extensions::OptionsExtension
    include Extensions::OptionsDefaults

    # @return [Integer]
    INITIAL_STARTING_POSITION = -1

    # @!attribute id
    #   @return [Integer]
    attribute(:id)
    # @!attribute partition_id
    #   @return [Integer]
    attribute(:partition_id)
    # @!attribute stream_id
    #   @return [String]
    attribute(:stream_id)
    # @!attribute stream_revision
    #   @return [Integer]
    attribute(:stream_revision)
    # @!attribute starting_position
    #   @return [Integer]
    attribute(:starting_position)
  end
end
