# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class RawEvent
    include Extensions::OptionsExtension
    include Extensions::OptionsDefaults

    # @!attribute id
    #   @return [String]
    attribute(:id)
    # @!attribute context
    #   @return [String]
    attribute(:context)
    # @!attribute stream_name
    #   @return [String]
    attribute(:stream_name)
    # @!attribute stream_id
    #   @return [String]
    attribute(:stream_id)
    # @!attribute global_position
    #   @return [Integer]
    attribute(:global_position)
    # @!attribute stream_revision
    #   @return [Integer]
    attribute(:stream_revision)
    # @!attribute data
    #   @return [Hash]
    attribute(:data)
    # @!attribute metadata
    #   @return [Hash]
    attribute(:metadata)
    # @!attribute link_partition_id
    #   @return [Integer, nil]
    attribute(:link_partition_id)
    # @!attribute created_at
    #   @return [Time]
    attribute(:created_at)
    # @!attribute type
    #   @return [String]
    attribute(:type)
    # @!attribute link_global_position
    #   @return [Integer, nil]
    attribute(:link_global_position)
  end
end
