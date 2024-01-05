# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventsFiltering
      DEFAULT_OFFSET = 0
      DEFAULT_LIMIT = 1000
      SQL_DIRECTIONS = {
        'asc' => 'ASC',
        'desc' => 'DESC',
        :asc => 'ASC',
        :desc => 'DESC',
        'Forwards' => 'ASC',
        'Backwards' => 'DESC'
      }.tap do |directions|
        directions.default = 'ASC'
      end.freeze

      class << self
        # @param options [Hash]
        # @param offset [Integer]
        # @return [PgEventstore::QueryBuilders::EventsFiltering]
        def all_stream_filtering(options, offset: 0)
          event_filter = new
          options in { filter: { event_type_ids: Array => event_type_ids } }
          event_filter.add_event_types(event_type_ids)
          event_filter.add_limit(options[:max_count])
          event_filter.add_offset(offset)
          event_filter.resolve_links(options[:resolve_link_tos])
          options in { filter: { streams: Array => streams } }
          streams&.each { |attrs| event_filter.add_stream_attrs(**attrs) }
          event_filter.add_global_position(options[:from_position], options[:direction])
          event_filter.add_all_stream_direction(options[:direction])
          event_filter
        end

        # @param stream [PgEventstore::Stream]
        # @param options [Hash]
        # @param offset [Integer]
        # @return [PgEventstore::QueryBuilders::EventsFiltering]
        def specific_stream_filtering(stream, options, offset: 0)
          event_filter = new
          options in { filter: { event_type_ids: Array => event_type_ids } }
          event_filter.add_event_types(event_type_ids)
          event_filter.add_limit(options[:max_count])
          event_filter.add_offset(offset)
          event_filter.resolve_links(options[:resolve_link_tos])
          event_filter.add_stream(stream)
          event_filter.add_revision(options[:from_revision], options[:direction])
          event_filter.add_stream_direction(options[:direction])
          event_filter
        end
      end

      def initialize
        @sql_builder =
          SQLBuilder.new.
            select('events.*').
            select('row_to_json(streams.*) as stream').
            select('event_types.type as type').
            from('events').
            join('JOIN streams ON streams.id = events.stream_id').
            join('JOIN event_types ON event_types.id = events.event_type_id').
            limit(DEFAULT_LIMIT).
            offset(DEFAULT_OFFSET)
      end

      # @param context [String, nil]
      # @param stream_name [String, nil]
      # @param stream_id [String, nil]
      # @return [void]
      def add_stream_attrs(context: nil, stream_name: nil, stream_id: nil)
        stream_attrs = { context: context, stream_name: stream_name, stream_id: stream_id }
        return unless correct_stream_filter?(stream_attrs)

        stream_attrs.compact!
        sql = stream_attrs.map do |attr, _|
          "streams.#{attr} = ?"
        end.join(" AND ")
        @sql_builder.where_or(sql, *stream_attrs.values)
      end

      # @param stream [PgEventstore::Stream]
      # @return [void]
      def add_stream(stream)
        @sql_builder.where("streams.id = ?", stream.id)
      end

      # @param event_type_ids [Array<Integer>, nil]
      # @return [void]
      def add_event_types(event_type_ids)
        return if event_type_ids.nil?
        return if event_type_ids.empty?

        sql = event_type_ids.size.times.map do
          "?"
        end.join(", ")
        @sql_builder.where("events.event_type_id IN (#{sql})", *event_type_ids)
      end

      # @param revision [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_revision(revision, direction)
        return unless revision

        @sql_builder.where("events.stream_revision #{direction_operator(direction)} ?", revision)
      end

      # @param position [Integer, nil]
      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_global_position(position, direction)
        return unless position

        @sql_builder.where("events.global_position #{direction_operator(direction)} ?", position)
      end

      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_stream_direction(direction)
        @sql_builder.order("events.stream_revision #{SQL_DIRECTIONS[direction]}")
      end

      # @param direction [String, Symbol, nil]
      # @return [void]
      def add_all_stream_direction(direction)
        @sql_builder.order("events.global_position #{SQL_DIRECTIONS[direction]}")
      end

      # @param limit [Integer, nil]
      # @return [void]
      def add_limit(limit)
        return unless limit

        @sql_builder.limit(limit)
      end

      # @param offset [Integer, nil]
      # @return [void]
      def add_offset(offset)
        return unless offset

        @sql_builder.offset(offset)
      end

      # @param should_resolve [Boolean]
      # @return [void]
      def resolve_links(should_resolve)
        return unless should_resolve

        @sql_builder.
          unselect.
          select("(COALESCE(original_events.*, events.*)).*").
          select('row_to_json(streams.*) as stream').
          join("LEFT JOIN events original_events ON original_events.id = events.link_id")
      end

      # @return [PgEventstore::SQLBuilder]
      def to_sql_builder
        @sql_builder
      end

      # @return [Array]
      def to_exec_params
        @sql_builder.to_exec_params
      end

      private

      # @param stream_attrs [Hash]
      # @return [Boolean]
      def correct_stream_filter?(stream_attrs)
        result = (stream_attrs in { context: String, stream_name: String, stream_id: String } |
          { context: String, stream_name: String, stream_id: nil } |
          { context: String, stream_name: nil, stream_id: nil })
        return true if result

        PgEventstore&.logger&.debug(<<~TEXT)
          Ignoring unsupported stream filter format for searching #{stream_attrs.compact.inspect}. \
          See docs/reading_events.md docs for supported formats.
        TEXT
        false
      end

      # @param direction [String, Symbol, nil]
      # @return [String]
      def direction_operator(direction)
        SQL_DIRECTIONS[direction] == 'ASC' ? '>=' : '<='
      end
    end
  end
end
