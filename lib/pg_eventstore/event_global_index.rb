# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventGlobalIndex
    include Extensions::OptionsExtension
    include Extensions::OptionsDefaults

    # @!attribute global_position
    #   @return [Integer]
    attribute(:global_position)
    # @!attribute stream_revision
    #   @return [Integer]
    attribute(:stream_revision)
    # @!attribute context_partition_id
    #   @return [Integer]
    attribute(:context_partition_id)
    # @!attribute stream_name_partition_id
    #   @return [Integer]
    attribute(:stream_name_partition_id)
    # @!attribute event_type_partition_id
    #   @return [Integer]
    attribute(:event_type_partition_id)
    # @!attribute streams_global_index_id
    #   @return [Integer]
    attribute(:streams_global_index_id)
    # @!attribute subscription_position
    #   @return [Integer]
    attribute(:subscription_position)

    # EventGlobalIndex representation that is used in subscriptions
    class SubscriptionRepr
      include Extensions::OptionsExtension
      include Extensions::OptionsDefaults

      # @!attribute global_position
      #   @return [Integer]
      attribute(:global_position)
      # @!attribute subscription_position
      #   @return [Integer]
      attribute(:subscription_position)
      # @!attribute event_type_partition_id
      #   @return [Integer]
      attribute(:event_type_partition_id)
    end

    # EventGlobalIndex representation that is used in Read API
    class ReadApiRepr
      include Extensions::OptionsExtension
      include Extensions::OptionsDefaults

      # @!attribute global_position
      #   @return [Integer]
      attribute(:global_position)
      # @!attribute event_type_partition_id
      #   @return [Integer]
      attribute(:event_type_partition_id)
    end

    # EventGlobalIndex representation that is used in Write API
    class WriteApiRepr
      include Extensions::OptionsExtension
      include Extensions::OptionsDefaults

      # @!attribute global_position
      #   @return [Integer]
      attribute(:global_position)
      # @!attribute event_type_partition_id
      #   @return [Integer]
      attribute(:event_type_partition_id)
      # @!attribute stream_revision
      #   @return [Integer]
      attribute(:stream_revision)
    end

    # EventGlobalIndex representation for revision validation in #append_to_stream
    class RevisionCheckRepr
      include Extensions::OptionsExtension
      include Extensions::OptionsDefaults

      # @!attribute stream_revision
      #   @return [Integer]
      attribute(:stream_revision)
      # @!attribute sequence_number
      #   @return [Integer]
      attribute(:sequence_number)
    end

    module ReprType
      SUBSCRIPTION = :subscription
      READ_API = :read_api
      WRITE_API = :write_api
      REVISION_CHECK = :revision_check
    end

    class << self
      # @param attributes [Hash<Symbol, Object>]
      # @param repr [Symbol, nil]
      # @return [EventGlobalIndex, SubscriptionRepr, ReadApiRepr, WriteApiRepr, RevisionCheckRepr]
      def create_representation(attributes, repr: nil)
        case repr
        when ReprType::SUBSCRIPTION
          SubscriptionRepr.new(**attributes)
        when ReprType::READ_API
          ReadApiRepr.new(**attributes)
        when ReprType::WRITE_API
          WriteApiRepr.new(**attributes)
        when ReprType::REVISION_CHECK
          RevisionCheckRepr.new(**attributes)
        else
          new(**attributes)
        end
      end
    end
  end
end
