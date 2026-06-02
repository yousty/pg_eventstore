# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class PartitionsFiltering
      include BasicFiltering

      # @return [String]
      TABLE_NAME = 'partitions'

      class << self
        # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
        # @param scope [Symbol] what kind of partition we want to receive. Available options are :event_type, :context,
        #   :stream_name and :auto. In :auto mode the scope will be calculated based on stream_filters and event_filters
        # @return [PgEventstore::SQLBuilder]
        def assemble_sql_builder(filters_collection, scope: :event_type)
          if filters_collection.has_event_types?
            # When event type filters are present - they apply constraints as is. Thus, we can't look up partitions by
            # stream attributes separately.
            filtering = new
            filters_collection.collection.each(&filtering.method(:add_filter_row))
            set_partitions_scope(filtering, has_stream_name_filter?(filters_collection), true, scope)
          else
            # When event type filters are absent - we can look up partitions by context and context/stream_name
            # separately, thus potentially producing one-to-one mapping of filter-to-partition with :auto scope. For
            # example, let's say we have stream attributes filter like
            # [{ context: 'FooCtx', stream_name: 'Bar'}, { context: 'BarCtx' }], then we would be able to look up
            # partitions by the exact match, returning only two of them according to the provided filters - stream
            # partition for first filter and context partition for second filter.
            builders = filters_collection.collection.map do |filter_row|
              filtering = new
              filtering.add_filter_row(filter_row)
              set_partitions_scope(filtering, filter_row.stream_filter.stream_name?, false, scope)
            end

            sql_builder = SQLBuilder.union_builders(builders) if builders.any?
            sql_builder ||
              begin
                filtering = new
                set_partitions_scope(filtering, has_stream_name_filter?(filters_collection), false, scope)
              end
          end
        end

        # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
        # @param scope [Symbol]
        # @return [PgEventstore::SQLBuilder]
        def from_filter_row(filter_row, scope: :event_type)
          filtering = new
          filtering.add_filter_row(filter_row)
          has_stream_name_filter = filter_row.stream_filter&.stream_name? || false
          has_event_type_filters = filter_row.event_type_filters.any?
          set_partitions_scope(filtering, has_stream_name_filter, has_event_type_filters, scope)
        end

        private

        # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
        # @return [Boolean]
        # rubocop:disable Naming/PredicatePrefix
        def has_stream_name_filter?(filters_collection)
          filters_collection.collection.any? { |filter_row| filter_row.stream_filter&.stream_name? }
        end
        # rubocop:enable Naming/PredicatePrefix

        # @param partitions_filtering [PgEventstore::QueryBuilders::PartitionsFiltering]
        # @param has_stream_name_filters [Boolean]
        # @param has_event_type_filters [Boolean]
        # @param scope [Symbol]
        # @return [PgEventstore::SQLBuilder]
        def set_partitions_scope(partitions_filtering, has_stream_name_filters, has_event_type_filters, scope)
          case scope
          when :event_type
            partitions_filtering.with_event_types
            partitions_filtering.order_by_event_type
          when :stream_name
            filter = QueryBuilders::PartitionsFiltering.new
            filter.without_event_types
            filter.with_stream_names
            filter.order_by_stream_name
            builder = filter.to_sql_builder
            builder.where(
              '(context, stream_name) in ?',
              partitions_filtering.
                to_sql_builder.
                unselect.
                select('distinct on (context, stream_name) context, stream_name')
            )
          when :context
            filter = QueryBuilders::PartitionsFiltering.new
            filter.without_event_types
            filter.without_stream_names
            filter.order_by_context
            builder = filter.to_sql_builder
            builder.where(
              'context in ?',
              partitions_filtering.
                to_sql_builder.
                unselect.
                select('distinct on (context) context')
            )
          when :auto
            if has_event_type_filters
              set_partitions_scope(partitions_filtering, has_stream_name_filters, has_event_type_filters, :event_type)
            elsif has_stream_name_filters
              set_partitions_scope(partitions_filtering, has_stream_name_filters, has_event_type_filters, :stream_name)
            else
              set_partitions_scope(partitions_filtering, has_stream_name_filters, has_event_type_filters, :context)
            end
          else
            raise NotImplementedError, "Don't know how to handle #{scope.inspect} scope!"
          end
        end
      end

      def initialize
        @sql_builder = SQLBuilder.new.select("#{to_table_name}.*").from(to_table_name)
      end

      def to_sql_builder
        @sql_builder
      end

      # @return [String]
      def to_table_name
        TABLE_NAME
      end

      # @param filter_row [PgEventstore::QueryBuilders::Filters::FilterRow]
      # @return [PgEventstore::SQLBuilder]
      def add_filter_row(filter_row)
        stream_filter = filter_row.stream_filter
        event_type_filters = filter_row.event_type_filters
        stream_parts_filters = []
        event_types_filters = []
        stream_filter&.to_partition_h&.each do |attr, value|
          stream_parts_filters.push(["#{to_table_name}.#{attr} = ?", value])
        end
        event_type_filters.each do |event_type_filter|
          comparison_part = event_type_filter.prefix? ? 'like' : '='
          event_types_filters.push(
            ["#{to_table_name}.event_type #{comparison_part} ?", event_type_filter.to_sql_value]
          )
        end

        stream_parts_filters_query, stream_parts_filters_values = stream_parts_filters.transpose
        event_types_query, event_types_values = event_types_filters.transpose
        sql = ''
        sql += stream_parts_filters_query.join(' and ') if stream_parts_filters_query&.any?
        sql += ' and ' if sql != '' && event_types_query&.any?
        sql += "(#{event_types_query.join(' or ')})" if event_types_query&.any?
        @sql_builder.where_or(sql, *stream_parts_filters_values, *event_types_values)
      end

      # @return [PgEventstore::SQLBuilder]
      def with_event_types
        with_stream_names
        @sql_builder.where('event_type IS NOT NULL')
      end

      # @return [PgEventstore::SQLBuilder]
      def with_stream_names
        @sql_builder.where('stream_name IS NOT NULL')
      end

      # @return [PgEventstore::SQLBuilder]
      def without_event_types
        @sql_builder.where('event_type IS NULL')
      end

      # @return [PgEventstore::SQLBuilder]
      def without_stream_names
        @sql_builder.where('stream_name IS NULL')
      end

      # @return [PgEventstore::SQLBuilder]
      def order_by_event_type
        @sql_builder.order('event_type asc, id asc')
      end

      # @return [PgEventstore::SQLBuilder]
      def order_by_stream_name
        @sql_builder.order('context asc, stream_name asc')
      end

      # @return [PgEventstore::SQLBuilder]
      def order_by_context
        @sql_builder.order('context asc')
      end
    end
  end
end
