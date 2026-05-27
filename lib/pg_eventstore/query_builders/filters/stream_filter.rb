# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      # @!visibility private
      class StreamFilter < Struct.new(:context, :stream_name, :stream_id)
        # @!attribute context
        #   @return [String]
        # @!attribute stream_name
        #   @return [String, nil]
        # @!attribute stream_id
        #   @return [String, nil]

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
          { context:, stream_name: }
        end

        # @return [Hash]
        def to_h
          { context:, stream_name:, stream_id: }.compact
        end
      end
    end
  end
end
