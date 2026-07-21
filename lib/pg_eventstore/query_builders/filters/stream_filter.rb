# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      # @!visibility private
      class StreamFilter
        include Extensions::OptionsExtension
        include Extensions::OptionsDefaults

        # @!attribute context
        #   @return [String]
        attribute(:context)
        # @!attribute stream_name
        #   @return [String, nil]
        attribute(:stream_name)
        # @!attribute stream_id
        #   @return [String, nil]
        attribute(:stream_id)

        # @return [Boolean]
        def context?
          stream_name.nil? && stream_id.nil?
        end

        # @return [Boolean]
        def stream_name?
          !stream_name.nil? && stream_id.nil?
        end

        # @return [Boolean]
        def stream?
          !stream_name.nil? && !stream_id.nil?
        end

        # @return [Hash]
        def to_partition_h
          { context:, stream_name: }.compact
        end

        # @return [Hash]
        def to_h
          { context:, stream_name:, stream_id: }.compact
        end
      end
    end
  end
end
