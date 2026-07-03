# frozen_string_literal: true

require_relative 'stream_filter'
require_relative 'event_type_filter'
require_relative 'filter_row'
require_relative 'marker_filter'
require_relative 'marker_filter_row'

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
          # @param event_types [Array<String>]
          # @return [void]
          def extract_event_types_filter(instance, event_types)
            event_types.each do |event_type|
              case event_type
              in String
                instance.add_event_type(EventTypeFilter.new(event_type: event_type, prefix: false))
              in { prefix: String => prefix }
                instance.add_event_type(EventTypeFilter.new(event_type: prefix, prefix: true))
              in { markers: Array => markers, **opts }
                str_markers = markers.grep(String)
                if str_markers.empty?
                  PgEventstore.logger&.debug("Unsupported #{event_type.inspect} markers filter.")
                  next
                end
                opts in { type: String => type }
                instance.add_marker(MarkerFilter.new(event_type: type, markers: str_markers))
              in { type: String => type }
                instance.add_event_type(EventTypeFilter.new(event_type: type, prefix: false))
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
          @markers = Set.new
          @prefix_filter = false
          @incomplete_stream_filter = false
          @incomplete_markers_filter = false
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
          @incomplete_stream_filter ||= stream_filter.context? || stream_filter.stream_name?
          @streams.index(stream_filter)
        end

        # @param event_type_filter [PgEventstore::QueryBuilders::Filters::EventTypeFilter]
        # @return [void]
        def add_event_type(event_type_filter)
          reset if @compiled
          @prefix_filter ||= event_type_filter.prefix?
          @event_types.add(event_type_filter)
        end

        # @param marker_filter [PgEventstore::QueryBuilders::Filters::MarkerFilter]
        # @return [void]
        def add_marker(marker_filter)
          reset if @compiled
          @incomplete_markers_filter ||= marker_filter.event_type.nil?
          @markers.add(marker_filter)
        end

        # rubocop:disable Naming/PredicatePrefix
        # @return [Boolean]
        def has_event_types?
          @event_types.any?
        end

        # @return [Boolean]
        def has_markers?
          @markers.any?
        end

        # @return [Boolean]
        def empty?
          @event_types.empty? && @streams.empty? && @markers.empty?
        end

        # @return [Boolean]
        def has_prefix_filter?
          @prefix_filter
        end

        # @return [Boolean]
        def has_incomplete_stream_filter?
          @incomplete_stream_filter
        end

        # @return [Boolean]
        def has_incomplete_markers_filter?
          @incomplete_markers_filter
        end
        # rubocop:enable Naming/PredicatePrefix

        private

        # @return [void]
        def reset
          @compiled = nil
        end

        # @return [void]
        def compile
          event_types_with_prefixes, event_types_without_prefixes = non_overlapping_event_types
          markers = non_overlapping_markers(event_types_with_prefixes, event_types_without_prefixes)
          event_types = event_types_with_prefixes + event_types_without_prefixes
          streams = @streams.find_non_overlapping
          @compiled =
            if streams.any?
              streams.flat_map do |stream_filter|
                rows = []
                rows << FilterRow.new(stream_filter:, event_type_filters: event_types) if has_event_types?
                markers.each do |marker_filter|
                  rows << MarkerFilterRow.new(stream_filter:, marker_filter:)
                end
                rows = [FilterRow.new(stream_filter:, event_type_filters: [])] if rows.empty?
                rows
              end
            else
              rows = []
              rows << FilterRow.new(event_type_filters: event_types) if has_event_types?
              markers.each do |marker_filter|
                rows << MarkerFilterRow.new(marker_filter:)
              end
              rows
            end
        end

        # @return [Array<Array<PgEventstore::QueryBuilders::Filters::EventTypeFilter>>]
        def non_overlapping_event_types
          with_prefixes = []
          without_prefixes = []
          @event_types.each do |event_type_filter|
            if event_type_filter.prefix?
              with_prefixes.push(event_type_filter)
            else
              without_prefixes.push(event_type_filter)
            end
          end
          return [[], without_prefixes] if with_prefixes.empty?

          with_prefixes = with_prefixes.sort_by(&:event_type)
          with_prefixes = with_prefixes.each_with_object([with_prefixes.first]) do |event_type_filter, result|
            result.push(event_type_filter) unless event_type_filter.event_type.start_with?(result.last.event_type)
          end

          without_prefixes = without_prefixes.reject do |event_type_filter|
            with_prefixes.any? { |prefix| event_type_filter.event_type.start_with?(prefix.event_type) }
          end
          [with_prefixes, without_prefixes]
        end

        # @param event_types_with_prefixes [Array<PgEventstore::QueryBuilders::Filters::EventTypeFilter>]
        # @param event_types_without_prefixes [Array<PgEventstore::QueryBuilders::Filters::EventTypeFilter>]
        # @return [Array<PgEventstore::QueryBuilders::Filters::MarkerFilter>]
        def non_overlapping_markers(event_types_with_prefixes, event_types_without_prefixes)
          markers = @markers.group_by(&:event_type).map do |event_type, filters|
            MarkerFilter.new(event_type:, markers: filters.flat_map(&:markers).uniq)
          end
          markers.reject do |marker|
            next false if marker.event_type.nil?

            marker_filter_overlaps_with_prefix_filter?(marker, event_types_with_prefixes) ||
              marker_filter_overlaps_with_event_type_filter?(marker, event_types_without_prefixes)
          end
        end

        # @param marker_filter [PgEventstore::QueryBuilders::Filters::MarkerFilter]
        # @param prefix_filters [Array<PgEventstore::QueryBuilders::Filters::EventTypeFilter>]
        # @return [Boolean]
        def marker_filter_overlaps_with_prefix_filter?(marker_filter, prefix_filters)
          prefix_filters.any? { marker_filter.event_type.start_with?(_1.event_type) }
        end

        # @param marker_filter [PgEventstore::QueryBuilders::Filters::MarkerFilter]
        # @param event_type_filters [Array<PgEventstore::QueryBuilders::Filters::EventTypeFilter>]
        def marker_filter_overlaps_with_event_type_filter?(marker_filter, event_type_filters)
          event_type_filter = EventTypeFilter.new(event_type: marker_filter.event_type, prefix: false)
          event_type_filters.include?(event_type_filter)
        end
      end
    end
  end
end
