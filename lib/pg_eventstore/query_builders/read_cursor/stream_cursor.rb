# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module ReadCursor
      # @!visibility private
      class StreamCursor
        class RegularStreamCursor < Struct.new(:from_revision, :to_revision, :direction, :max_count)
          # @!attribute from_revision
          #   @return [Integer, nil]
          # @!attribute to_revision
          #   @return [Integer, nil]
          # @!attribute direction
          #   @return [String, Symbol, nil]
          # @!attribute max_count
          #   @return [Integer, nil]
        end

        class AllStreamCursor < Struct.new(:from_position, :to_position, :direction, :max_count)
          # @!attribute from_position
          #   @return [Integer, nil]
          # @!attribute to_position
          #   @return [Integer, nil]
          # @!attribute direction
          #   @return [String, Symbol, nil]
          # @!attribute max_count
          #   @return [Integer, nil]
        end

        class << self
          # @param options [Hash]
          # @option options [Integer, nil] :from_position
          # @option options [Integer, nil] :to_position
          # @option options [String, Symbol, nil] :direction
          # @option options [Integer, nil] :max_count
          # @return [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
          def from_options(options)
            new(AllStreamCursor.new(**options.slice(*AllStreamCursor.members)))
          end

          # @param options [Hash]
          # @option options [Integer, nil] :from_position for "all" stream
          # @option options [Integer, nil] :to_position for "all" stream
          # @option options [Integer, nil] :from_revision for regular stream
          # @option options [Integer, nil] :to_revision for regular stream
          # @option options [String, Symbol, nil] :direction
          # @option options [Integer, nil] :max_count
          # @return [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
          def from_stream_and_options(stream, options)
            return new(AllStreamCursor.new(**options.slice(*AllStreamCursor.members))) if stream.all_stream?

            new(RegularStreamCursor.new(**options.slice(*RegularStreamCursor.members)))
          end
        end

        # @param cursor [ReadCursor::RegularStreamCursor, ReadCursor::RegularStreamCursor]
        def initialize(cursor)
          @cursor = cursor
        end

        # @return [Integer, nil]
        def from
          case @cursor
          when RegularStreamCursor
            @cursor.from_revision
          when AllStreamCursor
            @cursor.from_position
          else
            raise NotImplementedError
          end
        end

        # @return [Integer, nil]
        def to
          case @cursor
          when RegularStreamCursor
            @cursor.to_revision
          when AllStreamCursor
            @cursor.to_position
          else
            raise NotImplementedError
          end
        end

        # @return [String, Symbol, nil]
        def direction
          @cursor.direction
        end

        # @return [Integer, nil]
        def max_count
          @cursor.max_count
        end

        # @param val [Integer, nil]
        # @return [void]
        def max_count=(val)
          @cursor.max_count = val
        end

        # @return [Boolean]
        def all_stream_cursor?
          @cursor.is_a?(AllStreamCursor)
        end
      end
    end
  end
end
