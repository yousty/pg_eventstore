# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      # @!visibility private
      class MarkerFilterRow
        include Extensions::OptionsExtension
        include Extensions::OptionsDefaults

        # @!attribute stream_filter
        #   @return [PgEventstore::QueryBuilders::Filters::StreamFilter, nil]
        attribute(:stream_filter)
        # @!attribute stream_filter
        #   @return [PgEventstore::QueryBuilders::Filters::MarkerFilter]
        attribute(:marker_filter)

        # @return [Array<PgEventstore::QueryBuilders::Filters::MarkerFilterRow>]
        def flatten
          return [dup] if marker_filter.markers.size == 1

          marker_filter.markers.map do |marker|
            marker_filter = MarkerFilter.new(event_type: self.marker_filter.event_type, markers: [marker])
            self.class.new(stream_filter:, marker_filter:)
          end
        end

        # Event type is ambiguous in case we can't tell which partition it belongs to. We **can** tell the exact
        # partition of the given event type only when we have context and stream name as well.
        # @return [Boolean]
        def ambiguous_event_type?
          return true if !stream_filter.nil? && !stream_filter.stream? && marker_filter.event_type.nil?

          (stream_filter.nil? || stream_filter.context?) && !marker_filter.event_type.nil?
        end

        # @return [PgEventstore::QueryBuilders::Filters::FilterRow]
        def to_filter_row
          if marker_filter.event_type
            event_type_filter = EventTypeFilter.new(event_type: marker_filter.event_type, prefix: false)
            FilterRow.new(stream_filter:, event_type_filters: [event_type_filter])
          else
            FilterRow.new(stream_filter:, event_type_filters: [])
          end
        end
      end
    end
  end
end
