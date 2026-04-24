# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class PartitionsFiltering < BasicFiltering
      # @return [String]
      TABLE_NAME = 'partitions'
      private_constant :TABLE_NAME

      class << self
        # @param stream_filters [Array<Hash[Symbol, String]>]
        # @param event_filters [Array<String>]
        # @param scope [Symbol] what kind of partition we want to receive. Available options are :event_type, :context,
        #   :stream_name and :auto. In :auto mode the scope will be calculated based on stream_filters and event_filters
        # @return [PgEventstore::SQLBuilder]
        def assemble_sql_builder(stream_filters, event_filters, scope: :event_type)
          stream_filters = stream_filters.select { correct_stream_filter?(_1) }
          if event_filters.any?
            # When event type filters are present - they apply constraints to any stream filter. Thus, we can't look up
            # partitions by stream attributes separately.
            filter = new
            stream_filters.each { |attrs| filter.add_stream_attrs(**attrs) }
            filter.add_event_types(event_filters)
            set_partitions_scope(filter, stream_filters, event_filters, scope)
          else
            # When event type filters are absent - we can look up partitions by context and context/stream_name
            # separately, thus potentially producing one-to-one mapping of filter-to-partition with :auto scope. For
            # example, let's say we have stream attributes filter like
            # [{ context: 'FooCtx', stream_name: 'Bar'}, { context: 'BarCtx' }], then we would be able to look up
            # partitions by the exact match, returning only two of them according to the provided filters - stream
            # partition for first filter and context partition for second filter.
            builders = stream_filters.map do |attrs|
              filter = new
              filter.add_stream_attrs(**attrs)
              set_partitions_scope(filter, [attrs], event_filters, scope)
            end

            sql_builder = SQLBuilder.union_builders(builders) if builders.any?
            sql_builder ||
              begin
                filter = new
                set_partitions_scope(filter, stream_filters, event_filters, scope)
              end
          end
        end

        # @param options [Hash]
        # @return [Array<String>]
        def extract_event_types_filter(options)
          options in { filter: { event_types: Array => event_types } }
          event_types = event_types&.grep(String)
          event_types || []
        end

        # @param options [Hash]
        # @return [Array<Hash[Symbol, String]>]
        def extract_streams_filter(options)
          options in { filter: { streams: Array => streams } }
          streams = streams&.map do |stream_attrs|
            stream_attrs in { context: String | NilClass => context }
            stream_attrs in { stream_name: String | NilClass => stream_name }
            { context:, stream_name: }
          end
          streams || []
        end

        # @param stream_attrs [Hash]
        # @return [Boolean]
        def correct_stream_filter?(stream_attrs)
          result = (stream_attrs in { context: String, stream_name: String } | { context: String })
          return true if result

          PgEventstore.logger&.debug(<<~TEXT)
            Ignoring unsupported stream filter format for grouped read #{stream_attrs.compact.inspect}. \
            See docs/reading_events.md docs for supported formats.
          TEXT
          false
        end

        private

        # @param partitions_filter [PgEventstore::QueryBuilders::PartitionsFiltering]
        # @param stream_filters [Array<Hash[Symbol, String]>]
        # @param event_filters [Array<String>]
        # @param scope [Symbol]
        # @return [PgEventstore::SQLBuilder]
        def set_partitions_scope(partitions_filter, stream_filters, event_filters, scope)
          case scope
          when :event_type
            partitions_filter.with_event_types
          when :stream_name
            filter = QueryBuilders::PartitionsFiltering.new
            filter.without_event_types
            filter.with_stream_names
            builder = filter.to_sql_builder
            builder.where(
              '(context, stream_name) in ?',
              partitions_filter.to_sql_builder.unselect.select('context, stream_name').group('context, stream_name')
            )
          when :context
            filter = QueryBuilders::PartitionsFiltering.new
            filter.without_event_types
            filter.without_stream_names
            builder = filter.to_sql_builder
            builder.where('context in ?', partitions_filter.to_sql_builder.unselect.select('context').group('context'))
          when :auto
            if event_filters.any?
              set_partitions_scope(partitions_filter, stream_filters, event_filters, :event_type)
            elsif stream_filters.any? { _1[:stream_name] }
              set_partitions_scope(partitions_filter, stream_filters, event_filters, :stream_name)
            else
              set_partitions_scope(partitions_filter, stream_filters, event_filters, :context)
            end
          else
            raise NotImplementedError, "Don't know how to handle #{scope.inspect} scope!"
          end
        end
      end

      # @return [String]
      def to_table_name
        TABLE_NAME
      end

      # @param context [String, nil]
      # @param stream_name [String, nil]
      # @return [PgEventstore::SQLBuilder]
      def add_stream_attrs(context: nil, stream_name: nil)
        stream_attrs = { context:, stream_name: }
        return @sql_builder unless self.class.correct_stream_filter?(stream_attrs)

        stream_attrs.compact!
        sql = stream_attrs.map do |attr, _|
          "#{to_table_name}.#{attr} = ?"
        end.join(' AND ')
        @sql_builder.where_or(sql, *stream_attrs.values)
      end

      # @param event_types [Array<String>]
      # @return [PgEventstore::SQLBuilder]
      def add_event_types(event_types)
        return @sql_builder if event_types.empty?

        @sql_builder.where("#{to_table_name}.event_type = ANY(?::varchar[])", event_types)
      end

      # @return [PgEventstore::SQLBuilder]
      def with_event_types
        with_stream_names
        @sql_builder.where('event_type IS NOT NULL')
      end

      def with_stream_names
        @sql_builder.where('stream_name IS NOT NULL')
      end

      def without_event_types
        @sql_builder.where('event_type IS NULL')
      end

      def without_stream_names
        @sql_builder.where('stream_name IS NULL')
      end
    end
  end
end
