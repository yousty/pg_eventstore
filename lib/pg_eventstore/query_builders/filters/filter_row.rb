# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      class FilterRow < Struct.new(:stream_filter, :event_type_filters)
        def flatten
          return [self.class.new(stream_filter:, event_type_filters:)] if event_type_filters.none?

          event_type_filters.map do |event_type_filter|
            self.class.new(stream_filter:, event_type_filters: [event_type_filter])
          end
        end

        def collapsable_into_event_types_only?
          (stream_filter.nil? || stream_filter.context? || stream_filter.stream_name?) && event_type_filters.any?
        end
      end
    end
  end
end
