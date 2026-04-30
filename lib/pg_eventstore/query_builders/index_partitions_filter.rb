# frozen_string_literal: true

require_relative 'events_index_partition_constraint'
require_relative 'streams_index_partition_constraint'

module PgEventstore
  module QueryBuilders
    class IndexPartitionsFilter
      class << self
        def create_from_stream(stream)
          new(for_streams_idx: StreamsIndexPartitionConstraint.create({ filter: { streams: [stream.to_hash] } }))
        end

        # { streams: [{ context: 'Foo', stream_name: 'Bar' }, { context: 'Foo', stream_name: 'Baz', stream_id: '1' } ], event_types: ['Foo'] }
        def create(options)
          new(
            for_streams_idx: StreamsIndexPartitionConstraint.create(options),
            for_events_idx: EventsIndexPartitionConstraint.create(options)
          )
        end
      end

      def initialize(for_streams_idx: nil, for_events_idx: nil)
        @for_streams_idx = for_streams_idx
        @for_events_idx = for_events_idx
      end

      def for_streams_idx
        @for_streams_idx&.builders
      end

      def for_events_idx
        @for_events_idx&.builder
      end

      def empty?
        @for_streams_idx.nil? && @for_events_idx.nil?
      end

      def dup
        self.class.new(for_streams_idx: @for_streams_idx&.dup, for_events_idx: @for_events_idx&.dup)
      end
    end
  end
end
