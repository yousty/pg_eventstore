# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class SystemStreamReadPaginated < AbstractCommand
      # @see PgEventstore::Commands::Read for docs
      def call(stream, options: {})
        position = calc_initial_position(stream, options)
        Enumerator.new do |yielder|
          loop do
            events = read_cmd.call(stream, options: options.merge(from_position: position))
            yielder << events if events.any?
            raise StopIteration if end_reached?(events, options[:max_count])

            position = calc_next_position(events, options[:direction])
            raise StopIteration if position <= 0
          end
        end
      end

      private

      # @param stream [PgEventstore::Stream]
      # @param options [Hash]
      # @return [Integer]
      def calc_initial_position(stream, options)
        return options[:from_position] if options[:from_position]
        return 1 if forwards?(options[:direction])

        read_cmd.call(stream, options: options.merge(max_count: 1)).first.global_position
      end

      # @param events [Array<PgEventstore::Event>]
      # @param max_count [Integer]
      # @return [Boolean]
      def end_reached?(events, max_count)
        events.size < max_count
      end

      # @param events [Array<PgEventstore::Event>]
      # @param direction [String, Symbol, nil]
      # @return [Integer]
      def calc_next_position(events, direction)
        return events.last.global_position + 1 if forwards?(direction)

        events.last.global_position - 1
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
