# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module ReadCursor
      # @!visibility private
      class StreamCursor
        class RegularStreamCursor
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute from_revision
          #   @return [Integer, nil]
          attribute(:from_revision)
          # @!attribute to_revision
          #   @return [Integer, nil]
          attribute(:to_revision)
          # @!attribute direction
          #   @return [String, Symbol, nil]
          attribute(:direction)
          # @!attribute max_count
          #   @return [Integer, nil]
          attribute(:max_count)
        end

        class AllStreamCursor
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute from_position
          #   @return [Integer, nil]
          attribute(:from_position)
          # @!attribute to_position
          #   @return [Integer, nil]
          attribute(:to_position)
          # @!attribute direction
          #   @return [String, Symbol, nil]
          attribute(:direction)
          # @!attribute max_count
          #   @return [Integer, nil]
          attribute(:max_count)
        end

        class << self
          # @param options [Hash]
          # @option options [Integer, nil] :from_position
          # @option options [Integer, nil] :to_position
          # @option options [String, Symbol, nil] :direction
          # @option options [Integer, nil] :max_count
          # @return [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
          def from_options(options)
            new(AllStreamCursor.new(**options))
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
            return new(AllStreamCursor.new(**options)) if stream.all_stream?

            new(RegularStreamCursor.new(**options))
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
            Utils.missing_implementation!(@cursor)
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
            Utils.missing_implementation!(@cursor)
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
