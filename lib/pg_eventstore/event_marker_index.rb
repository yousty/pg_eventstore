# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventMarkerIndex
    include Extensions::OptionsExtension
    include Extensions::OptionsDefaults

    # @!attribute marker_id
    #   @return [Integer]
    attribute(:marker_id)
    # @!attribute streams_global_index_id
    #   @return [Integer]
    attribute(:streams_global_index_id)
    # @!attribute event_type_partition_id
    #   @return [Integer]
    attribute(:event_type_partition_id)
    # @!attribute global_position
    #   @return [Integer]
    attribute(:global_position)
    # @!attribute stream_revision
    #   @return [Integer]
    attribute(:stream_revision)
  end
end
