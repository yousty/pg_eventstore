# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    class EventsIndexPartitionConstraint
      class << self
        def create(options)
          stream_filters = EventsFiltering.extract_streams_filter(options).map(&:compact)
          event_type_filters = EventsFiltering.extract_event_types_filter(options)
          return if stream_filters.empty? && event_type_filters.empty?

          stream_filters_without_id = stream_filters.reject { _1[:stream_id] }
          builder = PartitionsFiltering.assemble_sql_builder(
            stream_filters_without_id, event_type_filters, scope: :event_type
          )
          builder = SQLBuilder.wrap_union_builder(builder) if builder.union_builder?
          builder.unselect.select('id')
          new(builder)
        end
      end

      attr_reader :builder

      def initialize(builder)
        @builder = builder
      end

      def dup
        self.class.new(builder.dup)
      end
    end
  end
end
