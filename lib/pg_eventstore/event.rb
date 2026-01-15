# frozen_string_literal: true

module PgEventstore
  class Event
    include Extensions::OptionsExtension

    # @return [String] a type of link event
    LINK_TYPE = '$>'
    # @return [String]
    PRIMARY_TABLE_NAME = 'events'

    # @!attribute id
    #   @return [String] UUIDv4 string
    attribute(:id)
    # @!attribute type
    #   @return [String] event type
    attribute(:type) { self.class.name }
    # @!attribute global_position
    #   @return [Integer] event's position in "all" stream
    attribute(:global_position)
    # @!attribute stream
    #   @return [PgEventstore::Stream, nil] event's stream
    attribute(:stream)
    # @!attribute stream_revision
    #   @return [Integer] a revision of an event inside event's stream
    attribute(:stream_revision)
    # @!attribute data
    #   @return [Hash] event's data
    attribute(:data) { {} }
    # @!attribute metadata
    #   @return [Hash] event's metadata
    attribute(:metadata) { {} }
    # @!attribute link_global_position
    #   @return [Integer, nil] global_position of an event the current event points to. If it is not nil, then the
    #     current event is a link
    attribute(:link_global_position)
    # @!attribute link_partition_id
    #   @return [Integer, nil] a partition id of an event the link event points to. It is used to load original event
    #     when resolve_link_tos: true option is provided when reading events.
    attribute(:link_partition_id)
    # @!attribute link
    #   @return [PgEventstore::Event, nil] when resolve_link_tos: true option is provided during the read of events and
    #     event is a link event - this attribute will be pointing on that link
    attribute(:link)
    # @!attribute created_at
    #   @return [Time, nil] a timestamp an event was created at
    attribute(:created_at)

    # Implements comparison of `PgEventstore::Event`-s. Two events matches if all of their attributes matches
    # @param other [Object, PgEventstore::Event]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(PgEventstore::Event)

      attributes_hash.except(:link) == other.attributes_hash.except(:link)
    end

    # Detect whether an event is a link event
    # @return [Boolean]
    def link?
      !link_global_position.nil?
    end

    # Detect whether an event is a system event
    # @return [Boolean]
    def system?
      type.start_with?('$')
    end
  end
end
