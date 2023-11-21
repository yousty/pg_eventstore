# frozen_string_literal: true

module PgEventstore
  class EventsFilteringQuery
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
      @streams = []
      @event_types = []
      @revision = nil
      @global_position = nil
      @direction = nil
      @limit = nil
      @offset = nil
      @resolve_links = false
    end

    # @param context [String, nil]
    # @param stream_name [String, nil]
    # @param stream_id [String, nil]
    # @return [void]
    def add_stream(context: nil, stream_name: nil, stream_id: nil)
      stream_attrs = { context: context, stream_name: stream_name, stream_id: stream_id }.compact
      return if stream_attrs.empty?

      @streams.push(stream_attrs)
    end

    # @param event_type [String, nil]
    # @return [void]
    def add_event_type(event_type)
      return if event_type.nil?

      @event_types.push(event_type)
    end

    # @param revision [Integer, nil]
    # @return [void]
    def add_revision(revision)
      @global_position = nil
      @revision = revision
    end

    # @param position [Integer, nil]
    # @return [void]
    def add_global_position(position)
      @revision = nil
      @global_position = position
    end

    # @param direction [String, Symbol, nil]
    # @return [void]
    def add_direction(direction)
      @direction = direction
    end

    # @param limit [Integer, nil]
    # @return [void]
    def add_limit(limit)
      @limit = limit
    end

    # @param offset [Integer, nil]
    # @return [void]
    def add_offset(offset)
      @offset = offset
    end

    # @param should_resolve [Boolean]
    # @return [void]
    def resolve_links(should_resolve)
      @resolve_links = should_resolve
    end

    # @return [Array]
    def to_exec_params
      sql =
        if @resolve_links
          <<~SQL
            SELECT (COALESCE(original_events.*, events.*)).* 
            FROM events
            LEFT JOIN events original_events ON original_events.global_position = events.link_id
          SQL
        else
          'SELECT * FROM events'
        end

      positional_values = []
      where_sql = [
        streams_sql(positional_values),
        event_types_sql(positional_values),
        stream_revision_sql(positional_values),
        global_position_sql(positional_values)
      ].reject(&:empty?).join(" AND ")
      sql += " WHERE #{where_sql}" unless where_sql.empty?

      sql += " ORDER BY events.global_position #{SQL_DIRECTIONS[@direction]}"

      positional_values.push(@limit || DEFAULT_LIMIT)
      sql += " LIMIT $#{positional_values.size}"
      positional_values.push(@offset || DEFAULT_OFFSET)
      sql += " OFFSET $#{positional_values.size}"

      [sql, positional_values]
    end

    private

    # @param positional_values [Array] a list of positional values for sql query
    # @return [String]
    def streams_sql(positional_values)
      sql = @streams.map do |stream_attrs|
        stream_parts = []
        stream_attrs.each do |column, value|
          positional_values.push(value)
          stream_parts.push "#{column} = $#{positional_values.size}"
        end
        "(#{stream_parts.join(" AND ")})"
      end.join(" OR ")
      sql = "(#{sql})" unless sql.empty?
      sql
    end

    # @param positional_values [Array] a list of positional values for sql query
    # @return [String]
    def event_types_sql(positional_values)
      sql = @event_types.map do |event_type|
        positional_values.push(event_type)
        "type = $#{positional_values.size}"
      end.join(" OR ")
      sql = "(#{sql})" unless sql.empty?
      sql
    end

    # @param positional_values [Array] a list of positional values for sql query
    # @return [String]
    def stream_revision_sql(positional_values)
      return '' unless @revision

      positional_values.push(@revision)
      "stream_revision >= $#{positional_values.size}"
    end

    # @param positional_values [Array] a list of positional values for sql query
    # @return [String]
    def global_position_sql(positional_values)
      return '' unless @global_position

      positional_values.push(@global_position)
      "global_position >= $#{positional_values.size}"
    end
  end
end
