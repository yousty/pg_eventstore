# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class StreamGlobalIndex < Struct.new(:id, :partition_id, :stream_id, :stream_revision, :starting_position,
                                       keyword_init: true)
    # @return [Integer]
    INITIAL_STARTING_POSITION = -1

    # @!attribute id
    #   @return [Integer]
    # @!attribute partition_id
    #   @return [Integer]
    # @!attribute stream_id
    #   @return [String]
    # @!attribute stream_revision
    #   @return [Integer]
    # @!attribute starting_position
    #   @return [Integer]
  end
end
