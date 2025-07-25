# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class PartitionsFiltering < BasicFiltering
      # @return [String]
      TABLE_NAME = 'partitions'
      private_constant :TABLE_NAME

      class << self
        # @param options [Hash]
        # @return [Array<String>]
        def extract_event_types_filter(options)
          options in { filter: { event_types: Array => event_types } }
          event_types = event_types&.select do
            _1.is_a?(String)
          end
          event_types || []
        end

        # @param options [Hash]
        # @return [Array<Hash[Symbol, String]>]
        def extract_streams_filter(options)
          options in { filter: { streams: Array => streams } }
          streams = streams&.map do
            _1 in { context: String | NilClass => context }
            _1 in { stream_name: String | NilClass => stream_name }
            { context: context, stream_name: stream_name }
          end
          streams || []
        end
      end

      # @return [String]
      def to_table_name
        TABLE_NAME
      end

      # @param context [String, nil]
      # @param stream_name [String, nil]
      # @return [void]
      def add_stream_attrs(context: nil, stream_name: nil)
        stream_attrs = { context: context, stream_name: stream_name }
        return unless correct_stream_filter?(stream_attrs)

        stream_attrs.compact!
        sql = stream_attrs.map do |attr, _|
          "#{to_table_name}.#{attr} = ?"
        end.join(" AND ")
        @sql_builder.where_or(sql, *stream_attrs.values)
      end

      # @param event_types [Array<String>]
      # @return [void]
      def add_event_types(event_types)
        return if event_types.empty?

        @sql_builder.where("#{to_table_name}.event_type = ANY(?::varchar[])", event_types)
      end

      # @return [void]
      def with_event_types
        @sql_builder.where('event_type IS NOT NULL')
      end

      private

      # @param stream_attrs [Hash]
      # @return [Boolean]
      def correct_stream_filter?(stream_attrs)
        result = (stream_attrs in { context: String, stream_name: String } | { context: String, stream_name: nil })
        return true if result

        PgEventstore&.logger&.debug(<<~TEXT)
          Ignoring unsupported stream filter format for grouped read #{stream_attrs.compact.inspect}. \
          See docs/reading_events.md docs for supported formats.
        TEXT
        false
      end
    end
  end
end
