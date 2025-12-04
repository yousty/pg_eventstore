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
          event_types = event_types&.select { _1.is_a?(String) }
          event_types || []
        end

        # @param options [Hash]
        # @return [Array<Hash[Symbol, String]>]
        def extract_streams_filter(options)
          options in { filter: { streams: Array => streams } }
          streams = streams&.map do |stream_attrs|
            stream_attrs in { context: String | NilClass => context }
            stream_attrs in { stream_name: String | NilClass => stream_name }
            { context: context, stream_name: stream_name }
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
      end

      # @return [String]
      def to_table_name
        TABLE_NAME
      end

      # @param context [String, nil]
      # @param stream_name [String, nil]
      # @return [PgEventstore::SQLBuilder]
      def add_stream_attrs(context: nil, stream_name: nil)
        stream_attrs = { context: context, stream_name: stream_name }
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
