# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      # @!visibility private
      class FilterRow
        include Extensions::OptionsExtension
        include Extensions::OptionsDefaults

        class << self
          # @return [PgEventstore::QueryBuilders::Filters::FilterRow]
          def null_filter_row
            new(event_type_filters: [EventTypeFilter.null_filter])
          end
        end

        # @!attribute stream_filter
        #   @return [PgEventstore::QueryBuilders::Filters::StreamFilter, nil]
        attribute(:stream_filter)
        # @!attribute event_type_filters
        #   @return [Array<PgEventstore::QueryBuilders::Filters::EventTypeFilter>]
        attribute(:event_type_filters)

        # @return [Array<PgEventstore::QueryBuilders::Filters::FilterRow>]
        def flatten
          return [dup] if event_type_filters.none?

          event_type_filters.map do |event_type_filter|
            self.class.new(stream_filter:, event_type_filters: [event_type_filter])
          end
        end

        # When we don't have stream filter or stream filter consists of only context or context and stream name, along
        # with event types filter - we can say that this row can be converted into event type only filter if needed.
        # This means we can craft a query by event_type_partition_id column only without involving other columns such as
        # context_partition_id, stream_name_partition_id or streams_global_index_id
        # @return [Boolean]
        def collapsable_into_event_types_only?
          (stream_filter.nil? || stream_filter.context? || stream_filter.stream_name?) && event_type_filters.any?
        end

        # Event type is ambiguous in case we can't tell which partition it belongs to. We **can** tell the exact
        # partition of the given event type only when we have context and stream name as well.
        # @return [Boolean]
        def ambiguous_event_type?
          return true if event_type_filters.any?(&:prefix?)

          (stream_filter.nil? || stream_filter.context?) && event_type_filters.any?
        end
      end
    end
  end
end
