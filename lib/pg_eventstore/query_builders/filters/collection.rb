# frozen_string_literal: true

require_relative 'stream_filter'
require_relative 'event_type_filter'
require_relative 'filter_row'

module PgEventstore
  module QueryBuilders
    module Filters
      # @!visibility private
      class Collection
        class << self
          # @param stream [PgEventstore::Stream]
          # @param options [Hash]
          # @return [self]
          def from_stream_and_options(stream, options)
            return from_options(options) if stream.all_stream?

            options in { filter: Hash => current_filter }
            current_filter = (current_filter || {}).except(:streams)
            from_options(options.merge(filter: { **current_filter, streams: [stream.to_hash] }))
          end

          # @param options [Hash]
          # @return [self]
          def from_options(options)
            instance = new
            case options
            in { filter: { streams: Array => streams, event_types: Array => event_types } }
              extract_streams_filter(instance, streams)
              extract_event_types_filter(instance, event_types)
            in { filter: { streams: Array => streams } }
              extract_streams_filter(instance, streams)
            in { filter: { event_types: Array => event_types } }
              extract_event_types_filter(instance, event_types)
            else
              # empty filters
            end
            instance
          end

          private

          # @param instance [PgEventstore::QueryBuilders::Filters::Collection]
          # @param event_types [Array<String>, nil]
          # @return [void]
          def extract_event_types_filter(instance, event_types)
            event_types&.each do |event_type|
              case event_type
              in String
                instance.add_event_type(EventTypeFilter.new(value: event_type, prefix: false))
              in { prefix: String => prefix }
                instance.add_event_type(EventTypeFilter.new(value: prefix, prefix: true))
              else
                PgEventstore.logger&.debug("Unsupported #{event_type.inspect} event type filter.")
              end
            end
          end

          # @param instance [PgEventstore::QueryBuilders::Filters::Collection]
          # @param streams [Array<Hash>, nil]
          # @return [void]
          def extract_streams_filter(instance, streams)
            streams&.each do |stream_attrs|
              matches = (stream_attrs in { context: String, stream_name: String, stream_id: String } |
                { context: String, stream_name: String } |
                { context: String })
              if matches
                instance.add_stream(StreamFilter.new(**stream_attrs.slice(:context, :stream_name, :stream_id)))
                next
              end

              unsupported_filter_warning(stream_attrs)
            end
          end

          # @param stream_attrs
          # @return [void]
          def unsupported_filter_warning(stream_attrs)
            PgEventstore.logger&.debug(<<~TEXT)
              Ignoring unsupported stream filter format for searching #{stream_attrs.inspect}. \
              See docs/reading_events.md docs for supported formats.
            TEXT
          end
        end

        # This class is responsible to index stream filters and compute non-overlapping collection of them. Two stream
        # filters overlap when one stream filter affects on the same or more partitions as another stream filter.
        # Example of overlapping filters:
        #   from_options(
        #     filter: {
        #       streams: [
        #         { context: 'FooCtx' },
        #         { context: 'FooCtx', stream_name: 'Bar' }
        #       ]
        #     }
        #   )
        # In this particular case first stream filter affects on all partitions of 'FooCtx' context, including those
        # partitions, which are related to 'Foo' stream name partitions from the second stream filter. Thus, was can
        # safely throw away the second filter and keep only the first one.
        # Example of non-overlapping filters:
        #   from_options(
        #     filter: {
        #       streams: [
        #         { context: 'FooCtx', stream_name: 'Foo' },
        #         { context: 'FooCtx', stream_name: 'Bar' }
        #       ]
        #     }
        #   )
        # This example shows that two filters affect on different set of partitions - ('FooCtx', 'Foo') and
        # ('FooCtx', 'Bar'). Thus, we keep both of them.
        class Index
          attr_reader :path
          attr_accessor :stream_filter

          def initialize
            @path = {}
            @stream_filter = nil
          end

          # @param stream_filter [PgEventstore::QueryBuilders::Filters::StreamFilter]
          # @return [void]
          def index(stream_filter)
            root = self
            stream_filter.to_h.each_value do |val|
              root.path[val] ||= self.class.new
              root = root.path[val]
            end
            root.stream_filter = stream_filter
          end

          # @return [Boolean]
          def empty?
            path.empty? && stream_filter.nil?
          end

          # @param root [PgEventstore::QueryBuilders::Filters::Collection::Index]
          # @return [Array<PgEventstore::QueryBuilders::Filters::StreamFilter>]
          def find_non_overlapping(root = self)
            return [root.stream_filter] if root.stream_filter

            root.path.each_value.flat_map do |branch|
              find_non_overlapping(branch)
            end
          end
        end
        private_constant :Index

        def initialize
          @streams = Index.new
          @event_types = Set.new
          @prefix_filter = false
          reset
        end

        # @return [Array<PgEventstore::QueryBuilders::Filters::FilterRow>]
        def collection
          compile unless @compiled
          @compiled
        end

        # @param stream_filter [PgEventstore::QueryBuilders::Filters::StreamFilter]
        # @return [void]
        def add_stream(stream_filter)
          reset if @compiled
          @streams.index(stream_filter)
        end

        # @param event_type_filter [PgEventstore::QueryBuilders::Filters::EventTypeFilter]
        # @return [void]
        def add_event_type(event_type_filter)
          reset if @compiled
          @prefix_filter ||= event_type_filter.prefix?
          @event_types.add(event_type_filter)
        end

        # rubocop:disable Naming/PredicatePrefix
        # @return [Boolean]
        def has_event_types?
          @event_types.any?
        end

        # @return [Boolean]
        def empty?
          @event_types.empty? && @streams.empty?
        end

        # @return [Boolean]
        def has_prefix_filter?
          @prefix_filter
        end
        # rubocop:enable Naming/PredicatePrefix

        private

        # @return [void]
        def reset
          @compiled = nil
        end

        # @return [void]
        def compile
          event_types = @event_types.to_a
          streams = @streams.find_non_overlapping
          @compiled =
            if streams.any?
              streams.map do |stream_filter|
                FilterRow.new(stream_filter:, event_type_filters: event_types)
              end
            elsif has_event_types?
              [FilterRow.new(event_type_filters: event_types)]
            else
              []
            end
        end
      end
    end
  end
end
