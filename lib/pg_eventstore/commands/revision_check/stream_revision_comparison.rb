# frozen_string_literal: true

module PgEventstore
  module Commands
    module RevisionCheck
      # @!visibility private
      class StreamRevisionComparison
        class << self
          # @param current_revision [Integer]
          # @param expected_revision [Integer, Symbol]
          # @return [Symbol]
          def verdict(current_revision, expected_revision)
            return if expected_revision == :any

            case [current_revision, expected_revision]
            in [Stream::NON_EXISTING_STREAM_REVISION, Integer]
              :expected_to_have_stream_with_given_revision
            in [Integer, Integer]
              :unmatched_stream_revision unless current_revision == expected_revision
            in [Integer, Symbol]
              if current_revision == Stream::NON_EXISTING_STREAM_REVISION && expected_revision == :stream_exists
                return :expected_to_have_stream
              end

              if current_revision > Stream::NON_EXISTING_STREAM_REVISION && expected_revision == :no_stream
                :expected_not_to_have_stream
              end
            else
              raise ArgumentError
            end
          end
        end
      end
    end
  end
end
