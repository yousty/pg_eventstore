# frozen_string_literal: true

require_relative 'stream_filter'
require_relative 'event_type_filter'
require_relative 'filter_row'

module PgEventstore
  module QueryBuilders
    module Filters
      class Collection
        class << self
          def from_stream_and_options(stream, options)
            return from_options(options) if stream.system?

            options in { filter: Hash => current_filter }
            current_filter = (current_filter || {}).except(:streams)
            from_options(options.merge(filter: { **current_filter, streams: [stream.to_hash] }))
          end

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

          def unsupported_filter_warning(stream_attrs)
            PgEventstore.logger&.debug(<<~TEXT)
              Ignoring unsupported stream filter format for searching #{stream_attrs.inspect}. \
              See docs/reading_events.md docs for supported formats.
            TEXT
          end
        end

        class Index
          attr_reader :children, :count

          def initialize
            @children = {}
            @count = 0
          end

          def index(stream_filter)
            root = self
            stream_filter.to_h.each_value do |val|
              root.children[val] ||= self.class.new
              root = root.children[val]
              root.incr!
            end
          end

          def incr!
            @count += 1
          end

          def uniq?(stream_filter)
            root = self
            stream_filter.to_h.each_value.each do |val|
              root = root.children[val]
            end
            root.count <= 1
          end
        end
        private_constant :Index

        def initialize
          @streams = Set.new
          @event_types = Set.new
          @index = Index.new
          @prefix_filter = false
          reset
        end

        def collection
          compile unless @compiled
          @compiled
        end

        def filters_unique?
          compile unless @compiled
          @filters_unique
        end

        def add_stream(stream_filter)
          reset if @compiled
          return if @streams.include?(stream_filter)

          @index.index(stream_filter)
          @streams.add(stream_filter)
        end

        def add_event_type(event_type_filter)
          reset if @compiled
          @prefix_filter ||= event_type_filter.prefix?
          @event_types.add(event_type_filter)
        end

        def to_partition_collection
          inst = self.class.new
          inst.event_types = @event_types.dup
          @streams.each do |stream_filter|
            inst.add_stream(stream_filter.to_partition_h)
          end
          inst
        end

        def has_event_types?
          @event_types.any?
        end

        def has_prefix_filter?
          @prefix_filter
        end

        protected

        def event_types=(val)
          @event_types = val
        end

        private

        def reset
          @compiled = nil
          @filters_unique = nil
        end

        def compile
          all_filters_unique = true
          event_types = @event_types.to_a
          @compiled =
            if @streams.any?
              @streams.map do |stream_filter|
                all_filters_unique &&= @index.uniq?(stream_filter)
                FilterRow.new(stream_filter:, event_type_filters: event_types)
              end
            elsif has_event_types?
              [FilterRow.new(event_type_filters: event_types)]
            else
              []
            end
          @filters_unique = all_filters_unique
        end
      end
    end
  end
end
