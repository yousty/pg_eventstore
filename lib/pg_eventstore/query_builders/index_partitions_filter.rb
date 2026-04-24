# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    class IndexPartitionsFilter
      class << self
        def create(options, scope:)
          stream_filters = EventsFiltering.extract_streams_filter(options).map(&:compact)
          event_type_filters = EventsFiltering.extract_event_types_filter(options)
          return new if stream_filters.empty? && event_type_filters.empty?

          filters_with_stream_id = stream_filters.select { _1[:stream_id] }
          if filters_with_stream_id.any?
            builders_with_stream_id = filters_with_stream_id.map do |filter|
              builder = PartitionsFiltering.assemble_sql_builder(
                [filter.except(:stream_id)],
                event_type_filters,
                scope:
              )
              stream_id = PG::Connection.escape(filter[:stream_id])
              builder = SQLBuilder.wrap_union_builder(builder) if builder.union_builder?
              builder.unselect.select("id, '#{stream_id}' as stream_id")
            end
            builder_without_stream_id = nil
            filters_without_stream_id = (stream_filters - filters_with_stream_id)
            if filters_without_stream_id.any?
              builder_without_stream_id = PartitionsFiltering.assemble_sql_builder(
                filters_without_stream_id,
                event_type_filters,
                scope:
              )
              if builder_without_stream_id.union_builder?
                builder_without_stream_id = SQLBuilder.wrap_union_builder(builder_without_stream_id)
              end
              builder_without_stream_id.unselect.select('id')
            end
            new(with_stream_ids: builders_with_stream_id, without_stream_id: builder_without_stream_id)
          else
            builder = PartitionsFiltering.assemble_sql_builder(stream_filters, event_type_filters, scope:)
            builder = SQLBuilder.wrap_union_builder(builder) if builder.union_builder?
            builder.unselect.select('id')
            new(without_stream_id: builder)
          end
        end
      end

      attr_reader :with_stream_ids, :without_stream_id

      def initialize(with_stream_ids: nil, without_stream_id: nil)
        @with_stream_ids = with_stream_ids
        @without_stream_id = without_stream_id
      end

      def empty?
        with_stream_ids.nil? && without_stream_id.nil?
      end

      def dup
        self.class.new(with_stream_ids: with_stream_ids&.map(&:dup), without_stream_id: without_stream_id.dup)
      end
    end
  end
end
