# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
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

      def initialize
        @sql_builder =
          SQLBuilder.new.
            select('events.*').
            select('row_to_json(streams.*) as stream').
            from('events').
            join('JOIN streams ON streams.id = events.stream_id').
            limit(DEFAULT_LIMIT).
            offset(DEFAULT_OFFSET)
      end

      # @param context [String, nil]
      # @param stream_name [String, nil]
      # @param stream_id [String, nil]
      # @return [void]
      def add_stream_attrs(context: nil, stream_name: nil, stream_id: nil)
        stream_attrs = { context: context, stream_name: stream_name, stream_id: stream_id }.compact
        return if stream_attrs.empty?

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

      # @param event_types [Array, nil]
      # @return [void]
      def add_event_types(event_types)
        return if event_types.nil?
        return if event_types.empty?

        sql = event_types.size.times.map do
          "events.type = ?"
        end.join(" OR ")
        @sql_builder.where(sql, *event_types)
      end

      # @param revision [Integer, nil]
      # @return [void]
      def add_revision(revision)
        return unless revision

        @sql_builder.where("events.stream_revision >= ?", revision)
      end

      # @param position [Integer, nil]
      # @return [void]
      def add_global_position(position)
        return unless position

        @sql_builder.where("events.global_position >= ?", position)
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

      # @return [Array]
      def to_exec_params
        @sql_builder.to_exec_params
      end
    end
  end
end
