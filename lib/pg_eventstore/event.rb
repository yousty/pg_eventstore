# frozen_string_literal: true

module PgEventstore
  class Event
    include Extensions::OptionsExtension

    # @!attribute id
    #   @return [String] UUIDv4 string
    attribute(:id)
    # @!attribute type
    #   @return [String] event type
    attribute(:type) { self.class.name }
    # @!attribute global_position
    #   @return [Integer] event's position in "all" stream
    attribute(:global_position)
    # @!attribute context
    #   @return [String] context of event's stream
    attribute(:context)
    # @!attribute stream_name
    #   @return [String] event's stream name
    attribute(:stream_name)
    # @!attribute stream_id
    #   @return [String] event's stream id
    attribute(:stream_id)
    # @!attribute stream_revision
    #   @return [Integer] a revision of an event inside event's stream
    attribute(:stream_revision)
    # @!attribute data
    #   @return [Hash] event's data
    attribute(:data) { {} }
    # @!attribute metadata
    #   @return [Hash] event's metadata
    attribute(:metadata) { {} }
    # @!attribute link_id
    #   @return [Integer, nil] a global id of an event the current event points to. If it is not nil, then the current
    #     event is a link
    attribute(:link_id)
    # @!attribute created_at
    #   @return [Time, nil] a timestamp an event was created at
    attribute(:created_at)

    # @return [PgEventstore::Stream]
    def stream
      Stream.new(context: context, stream_name: stream_name, stream_id: stream_id)
    end

    # Implements comparison of `PgEventstore::Event`-s. Two events matches if all of their attributes matches
    # @param other [Object, EventStoreClient::DeserializedEvent]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(PgEventstore::Event)

      attributes_hash == other.attributes_hash
    end

    # Detect whether an event is a link event
    # @return [Boolean]
    def link?
      !link_id.nil?
    end
  end
end
