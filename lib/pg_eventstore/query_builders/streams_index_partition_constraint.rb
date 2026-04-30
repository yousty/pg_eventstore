# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    class StreamsIndexPartitionConstraint
      class << self
        def create(options)
          stream_filters = EventsFiltering.extract_streams_filter(options).map(&:compact)
          event_type_filters = EventsFiltering.extract_event_types_filter(options)
          return if stream_filters.empty? && event_type_filters.empty?

          filters_with_stream_id = stream_filters.select { _1[:stream_id] }
          return unless filters_with_stream_id.any?

          builders_with_stream_id = filters_with_stream_id.map do |filter|
            builder = PartitionsFiltering.assemble_sql_builder(
              [filter.except(:stream_id)],
              event_type_filters,
              scope: :stream_name
            )
            stream_id = PG::Connection.escape(filter[:stream_id])
            builder = SQLBuilder.wrap_union_builder(builder) if builder.union_builder?
            builder.unselect.select("id, '#{stream_id}' as stream_id")
          end
          new(builders_with_stream_id)
        end
      end

      attr_reader :builders

      def initialize(builders)
        @builders = builders
      end

      def dup
        self.class.new(builders.map(&:dup))
      end
    end
  end
end
