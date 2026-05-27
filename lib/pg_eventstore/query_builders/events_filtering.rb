# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventsFiltering
      include BasicFiltering

      # @return [Integer]
      DEFAULT_LIMIT = 1_000

      def initialize
        @sql_builder = SQLBuilder.new.select("#{to_table_name}.*").from(to_table_name)
      end

      def to_sql_builder
        @sql_builder
      end

      # @return [String]
      def to_table_name
        Event::PRIMARY_TABLE_NAME
      end

      # @param context [String]
      # @param stream_name [String]
      # @return [void]
      def add_stream_attrs(context:, stream_name:)
        @sql_builder.where_or('context = ? and stream_name = ?', context, stream_name)
      end

      # @param event_types [Array<String>]
      # @return [void]
      def add_event_types(event_types)
        return if event_types.empty?

        sql = event_types.size.times.map do
          '?'
        end.join(', ')
        @sql_builder.where("#{to_table_name}.type #{comparison_operator(event_types)} (#{sql})", *event_types)
      end

      # @param limit [Integer, nil]
      # @return [void]
      def add_limit(limit)
        @sql_builder.limit(limit || DEFAULT_LIMIT)
      end

      private

      def comparison_operator(event_types)
        event_types.size > 1 ? 'in' : '='
      end
    end
  end
end
