# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class RegularStreamReadPaginated < AbstractCommand
      # @see PgEventstore::Commands::Read for docs
      def call(stream, options: {})
        Enumerator.new do |yielder|
          next_revision = nil
          loop do
            options = options.merge(from_revision: next_revision) if next_revision
            events = read_cmd.call(stream, options:)
            yielder << events if events.any?
            if end_reached?(events, options[:max_count] || QueryBuilders::EventsFiltering::DEFAULT_LIMIT)
              raise StopIteration
            end

            next_revision = calc_next_revision(events, options[:direction])
            raise StopIteration if next_revision < 0
          end
        end
      end

      private

      # @param events [Array<PgEventstore::Event>]
      # @param max_count [Integer]
      # @return [Boolean]
      def end_reached?(events, max_count)
        events.size < max_count
      end

      # @param events [Array<PgEventstore::Event>]
      # @param direction [String, Symbol, nil]
      # @return [Integer]
      def calc_next_revision(events, direction)
        return events.last.stream_revision + 1 if forwards?(direction)

        events.last.stream_revision - 1
      end

      # @param direction [String, Symbol, nil]
      # @return [Boolean]
      def forwards?(direction)
        QueryBuilders::EventsFiltering::SQL_DIRECTIONS[direction] == QueryBuilders::EventsFiltering::SQL_DIRECTIONS[:asc]
      end

      # @return [PgEventstore::Commands::Read]
      def read_cmd
        @read_cmd ||= Read.new(queries)
      end
    end
  end
end
