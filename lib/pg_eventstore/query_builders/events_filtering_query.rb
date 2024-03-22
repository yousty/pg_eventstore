# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventsFiltering
      DEFAULT_LIMIT = 1_000
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
      SUBSCRIPTIONS_OPTIONS = %i[from_position resolve_link_tos filter max_count].freeze

      class << self
        # @param options [Hash]
        # @return [PgEventstore::QueryBuilders::EventsFiltering]
        def subscriptions_events_filtering(options)
          all_stream_filtering(options.slice(*SUBSCRIPTIONS_OPTIONS))
        end

        # @param options [Hash]
        # @return [PgEventstore::QueryBuilders::EventsFiltering]
        def all_stream_filtering(options)
          event_filter = new
          options in { filter: { event_types: Array => event_types } }
          event_filter.add_event_types(event_types)
          event_filter.add_limit(options[:max_count])
          options in { filter: { streams: Array => streams } }
          streams&.each { |attrs| event_filter.add_stream_attrs(**attrs) }
          event_filter.add_global_position(options[:from_position], options[:direction])
          event_filter.add_all_stream_direction(options[:direction])
          event_filter
        end

        # @param stream [PgEventstore::Stream]
        # @param options [Hash]
        # @return [PgEventstore::QueryBuilders::EventsFiltering]
        def specific_stream_filtering(stream, options)
          event_filter = new
          options in { filter: { event_types: Array => event_types } }
          event_filter.add_event_types(event_types)
          event_filter.add_limit(options[:max_count])
          event_filter.add_stream_attrs(**stream.to_hash)
          event_filter.add_revision(options[:from_revision], options[:direction])
          event_filter.add_stream_direction(options[:direction])
          event_filter
        end
      end

      def initialize
        @sql_builder =
          SQLBuilder.new.
            select('events.*').
            from('events').
            limit(DEFAULT_LIMIT)
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
          "events.#{attr} = ?"
        end.join(" AND ")
        @sql_builder.where_or(sql, *stream_attrs.values)
      end

      # @param event_types [Array<String>, nil]
      # @return [void]
      def add_event_types(event_types)
        return if event_types.nil?
        return if event_types.empty?

        sql = event_types.size.times.map do
          "?"
        end.join(", ")
        @sql_builder.where("events.type IN (#{sql})", *event_types)
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
