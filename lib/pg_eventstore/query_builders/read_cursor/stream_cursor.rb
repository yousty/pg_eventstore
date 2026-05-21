# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module ReadCursor
      class StreamCursor
        RegularStreamCursor = Struct.new(:from_revision, :to_revision, :direction, :max_count)
        SystemStreamCursor = Struct.new(:from_position, :to_position, :direction, :max_count)

        class << self
          def from_options(options)
            new(SystemStreamCursor.new(**options.slice(*SystemStreamCursor.members)))
          end

          def from_stream_and_options(stream, options)
            return new(SystemStreamCursor.new(**options.slice(*SystemStreamCursor.members))) if stream.system?

            new(RegularStreamCursor.new(**options.slice(*RegularStreamCursor.members)))
          end
        end

        def initialize(cursor)
          @cursor = cursor
        end

        def from
          case @cursor
          when RegularStreamCursor
            @cursor.from_revision
          when SystemStreamCursor
            @cursor.from_position
          else
            NotImplementedError
          end
        end

        def to
          case @cursor
          when RegularStreamCursor
            @cursor.to_revision
          when SystemStreamCursor
            @cursor.to_position
          else
            NotImplementedError
          end
        end

        def direction
          @cursor.direction
        end

        def max_count
          @cursor.max_count
        end

        def max_count=(val)
          @cursor.max_count = val
        end

        def system_stream_cursor?
          @cursor.is_a?(SystemStreamCursor)
        end
      end
    end
  end
end
