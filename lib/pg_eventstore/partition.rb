# frozen_string_literal: true

module PgEventstore
  class Partition
    include Extensions::OptionsExtension

    # @!attribute id
    #   @return [Integer]
    option(:id)
    # @!attribute context
    #   @return [String]
    option(:context)
    # @!attribute stream_name
    #   @return [String, nil]
    option(:stream_name)
    # @!attribute event_type
    #   @return [String, nil]
    option(:event_type)
    # @!attribute table_name
    #   @return [String]
    option(:table_name)
  end
end
