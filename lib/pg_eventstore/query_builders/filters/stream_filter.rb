# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      class StreamFilter < Struct.new(:context, :stream_name, :stream_id)
        def context?
          stream_name.nil? && stream_id.nil?
        end

        def stream_name?
          !stream_name.nil? && stream_id.nil?
        end

        def stream?
          !stream_name.nil? && !stream_id.nil?
        end

        def to_partition_h
          { context:, stream_name: }
        end

        def to_h
          { context:, stream_name:, stream_id: }.compact
        end
      end
    end
  end
end
