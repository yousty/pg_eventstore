# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class ReadStreamsPaginated < AbstractCommand
      def call(options: {})
        Enumerator.new do |yielder|
          next_position = nil
          loop do
            options = options.merge(from_position: next_position) if next_position
            indexes = queries.streams_global_index.streams_global_index(options)
            streams = queries.streams_global_index.resolve_indexes(indexes)
            yielder << streams if streams.any?
            if end_reached?(streams, options[:max_count] || QueryBuilders::StreamsGlobalIndexFiltering::DEFAULT_LIMIT)
              raise StopIteration
            end

            next_position = calc_next_position(indexes, options[:direction])
            raise StopIteration if next_position <= 0
          end
        end
      end

      private

      # @param streams [Array<PgEventstore::Stream>]
      # @param max_count [Integer]
      # @return [Boolean]
      def end_reached?(streams, max_count)
        streams.size < max_count
      end

      # @param indexes [Array<PgEventstore::StreamGlobalIndex>]
      # @param direction [String, Symbol, nil]
      # @return [Integer]
      def calc_next_position(indexes, direction)
        return indexes.last.starting_position + 1 if forwards?(direction)

        indexes.last.starting_position - 1
      end

      # @param direction [String, Symbol, nil]
      # @return [Boolean]
      def forwards?(direction)
        QueryBuilders::StreamsGlobalIndexFiltering::SQL_DIRECTIONS[direction] ==
          QueryBuilders::StreamsGlobalIndexFiltering::SQL_DIRECTIONS[:asc]
      end
    end
  end
end
