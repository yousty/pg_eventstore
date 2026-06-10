# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      # @!visibility private
      class FilterRow
        include Extensions::OptionsExtension
        include Extensions::OptionsDefaults

        # @!attribute stream_filter
        #   @return [PgEventstore::QueryBuilders::Filters::StreamFilter, nil]
        attribute(:stream_filter)
        # @!attribute event_type_filters
        #   @return [Array<PgEventstore::QueryBuilders::Filters::EventTypeFilter>]
        attribute(:event_type_filters)

        # @return [Array<PgEventstore::QueryBuilders::Filters::FilterRow>]
        def flatten
          return [self.class.new(stream_filter:, event_type_filters:)] if event_type_filters.none?

          event_type_filters.map do |event_type_filter|
            self.class.new(stream_filter:, event_type_filters: [event_type_filter])
          end
        end

        # @return [Boolean]
        def collapsable_into_event_types_only?
          (stream_filter.nil? || stream_filter.context? || stream_filter.stream_name?) && event_type_filters.any?
        end

        # @return [Boolean]
        def ambiguous_event_type?
          (stream_filter.nil? || stream_filter.context?) && event_type_filters.any?
        end
      end
    end
  end
end
