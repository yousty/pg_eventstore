# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventsGlobalIndexFiltering
      include BasicFiltering

      # @return [Integer]
      DEFAULT_LIMIT = 1_000
      # @return [String]
      PRIMARY_TABLE_NAME = 'events_global_index'

      class << self
        # @param options [Hash]
        # @return [PgEventstore::QueryBuilders::EventsGlobalIndexFiltering]
        def build(options)
          filter_collection = Filters::Collection.from_options(options)
          index_filtering = new
          filter_collection.collection.each(&index_filtering.method(:add_filter_row))
          index_filtering.from_position(options[:from_position], options[:direction])
          index_filtering.to_position(options[:to_position], options[:direction])
          index_filtering.add_global_position_direction(options[:direction])
          index_filtering.add_limit(options[:max_count])
          index_filtering
        end

        def build_grouped_for_read_api(stream, options)
          filter_collection = Filters::Collection.from_stream_and_options(stream, options)
          if filter_collection.has_prefix_filter?
            raise NotSupportedError, 'Read API does not support look up by prefix.'
          end
          raise 'This operation requires event type filter' unless filter_collection.has_event_types?

          options = options.merge(max_count: 1)
          builders = filter_collection.collection.flat_map do |filter_row|
            filter_row.flatten.map { filtering_from_filter_row(_1, stream, options).to_sql_builder }
          end
          SQLBuilder.union_builders(builders, mode: filter_collection.filters_unique? ? :all : :distinct)
        end

        def build_for_read_api(stream, options)
          filter_collection = Filters::Collection.from_stream_and_options(stream, options)
          if filter_collection.has_prefix_filter?
            raise NotSupportedError, 'Read API does not support look up by prefix.'
          end

          builders = filter_collection.collection.flat_map do |filter_row|
            filter_row.flatten.map { filtering_from_filter_row(_1, stream, options).to_sql_builder }
          end
          return default_filtering(stream, options) if builders.empty?

          union_builders(builders, stream, options, mode: filter_collection.filters_unique? ? :all : :distinct)
        end

        private

        def union_builders(builders, stream, options, mode:)
          return builders.first if builders.size == 1

          union_builder = SQLBuilder.union_builders(builders, mode:)
          top_filtering = new
          add_direction_and_limit(top_filtering, stream, options)
          top_filtering.to_sql_builder.from(union_builder)
        end

        def filtering_from_filter_row(filter_row, stream, options)
          index_filtering = default_filtering(stream, options)
          index_filtering.add_filter_row(filter_row)
          index_filtering
        end

        def default_filtering(stream, options)
          index_filtering = new
          add_direction_and_limit(index_filtering, stream, options)
          if stream.system?
            index_filtering.from_position(options[:from_position], options[:direction])
            index_filtering.to_position(options[:to_position], options[:direction])
          else
            index_filtering.from_revision(options[:from_revision], options[:direction])
            index_filtering.to_revision(options[:to_revision], options[:direction])
          end
          index_filtering
        end

        def add_direction_and_limit(index_filtering, stream, options)
          if stream.system?
            index_filtering.add_global_position_direction(options[:direction])
          else
            index_filtering.add_stream_revision_direction(options[:direction])
          end
          index_filtering.add_limit(options[:max_count])
        end
      end

      def initialize
        @sql_builder = SQLBuilder.new
        @sql_builder.select("#{to_table_name}.global_position, #{to_table_name}.event_type_partition_id")
        @sql_builder.from(to_table_name)
      end

      def to_sql_builder
        @sql_builder
      end

      # @return [String]
      def to_table_name
        PRIMARY_TABLE_NAME
      end

      def add_filter_row(filter_row)
        stream_filter = filter_row.stream_filter
        event_type_filters = filter_row.event_type_filters
        # Collapse context/stream name & event type filters into event type filters
        if filter_row.collapsable_into_event_types_only?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row)
          partitions_builder = affected_partitions.unselect.select('id')
          comparison_operator = comparison_operator(event_type_filters)
          return @sql_builder.where_or("event_type_partition_id #{comparison_operator} ?", partitions_builder)
        end

        query_parts = []
        case
        when stream_filter&.stream?
          streams_filter = StreamsGlobalIndexFiltering.new
          streams_filter.add_filter_row(filter_row)
          query_parts << ['streams_global_index_id = ?', streams_filter.to_sql_builder.unselect.select('id')]
        when stream_filter&.context?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row, scope: :context)
          query_parts << ['context_partition_id = ?', affected_partitions.unselect.select('id')]
        when stream_filter&.stream_name?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row, scope: :stream_name)
          query_parts << ['stream_name_partition_id = ?', affected_partitions.unselect.select('id')]
        end

        if event_type_filters.any?
          affected_partitions = PartitionsFiltering.from_filter_row(filter_row)
          query_parts << [
            "event_type_partition_id #{comparison_operator(event_type_filters)} ?",
            affected_partitions.unselect.select('id'),
          ]
        end

        attributes_sql, values = query_parts.transpose
        @sql_builder.where_or(attributes_sql.join(' and '), *values)
      end

      # @param position [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def from_position(position, direction)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position #{direction_operator_from(direction)} ?", position)
      end

      # @param revision [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def from_revision(revision, direction)
        return unless revision

        @sql_builder.where("#{to_table_name}.stream_revision #{direction_operator_from(direction)} ?", revision)
      end

      # @param position [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def to_position(position, direction)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position #{direction_operator_to(direction)} ?", position)
      end

      # @param revision [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def to_revision(revision, direction)
        return unless revision

        @sql_builder.where("#{to_table_name}.stream_revision #{direction_operator_to(direction)} ?", revision)
      end

      # @param limit [Integer, nil]
      # @return [void]
      def add_limit(limit = DEFAULT_LIMIT)
        return unless limit

        @sql_builder.limit(limit)
      end

      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_global_position_direction(direction)
        @sql_builder.order("#{to_table_name}.global_position #{SQL_DIRECTIONS[direction]}")
      end

      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_stream_revision_direction(direction)
        @sql_builder.order("#{to_table_name}.stream_revision #{SQL_DIRECTIONS[direction]}")
      end

      # @param table_name [String] system stream view name
      # @return [void]
      # rubocop:disable Naming/AccessorMethodName
      def set_source(table_name)
        @sql_builder.from(%( "#{PG::Connection.escape(table_name)}" #{to_table_name} ))
      end
      # rubocop:enable Naming/AccessorMethodName

      private

      # @param direction [String, Symbol, nil]
      # @return [String]
      def direction_operator_from(direction)
        SQL_DIRECTIONS[direction] == 'ASC' ? '>=' : '<='
      end

      # @param direction [String, Symbol, nil]
      # @return [String]
      def direction_operator_to(direction)
        SQL_DIRECTIONS[direction] == 'ASC' ? '<=' : '>='
      end

      def comparison_operator(entities)
        entities.size > 1 || entities.any?(&:prefix?) ? 'in' : '='
      end
    end
  end
end
