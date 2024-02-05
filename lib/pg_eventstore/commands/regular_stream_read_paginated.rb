# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class RegularStreamReadPaginated < AbstractCommand
      # @see PgEventstore::Commands::Read for docs
      def call(stream, options: {})
        revision = calc_initial_revision(stream, options)
        Enumerator.new do |yielder|
          loop do
            events = read_cmd.call(stream, options: options.merge(from_revision: revision))
            yielder << events if events.any?
            raise StopIteration if end_reached?(events, options[:max_count])

            revision = calc_next_revision(events, revision, options[:direction])
            raise StopIteration if revision.negative?
          end
        end
      end

      private

      # @param stream [PgEventstore::Stream]
      # @param options [Hash]
      # @return [Integer]
      def calc_initial_revision(stream, options)
        return options[:from_revision] if options[:from_revision]
        return 0 if forwards?(options[:direction])

        read_cmd.call(stream, options: options.merge(max_count: 1)).first.stream_revision
      end

      # @param events [Array<PgEventstore::Event>]
      # @param max_count [Integer]
      # @return [Boolean]
      def end_reached?(events, max_count)
        events.size < max_count
      end

      # @param events [Array<PgEventstore::Event>]
      # @param revision [Integer]
      # @param direction [String, Symbol, nil]
      # @return [Integer]
      def calc_next_revision(events, revision, direction)
        return revision + events.size if forwards?(direction)

        revision - events.size
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
