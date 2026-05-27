# frozen_string_literal: true

module PgEventstore
  module Commands
    module RevisionCheck
      # @!visibility private
      class EventTypeRevisionsComparison
        class << self
          # @param current_revision [Integer]
          # @param expected_revision [Symbol, Integer]
          # @param event_type [String]
          # @return [[Symbol, String]]
          def verdict(current_revision, expected_revision, event_type)
            return if expected_revision == :any

            case [current_revision, expected_revision]
            in [Event::NON_EXISTING_EVENT_REVISION, Integer]
              [:expected_to_have_event_with_given_revision, event_type]
            in [Integer, Integer]
              [:unmatched_event_revision, event_type] unless current_revision == expected_revision
            in [Integer, Symbol]
              if current_revision == Event::NON_EXISTING_EVENT_REVISION && expected_revision == :event_exists
                return [:expected_to_have_event, event_type]
              end

              if current_revision > Event::NON_EXISTING_EVENT_REVISION && expected_revision == :no_event
                [:expected_not_to_have_event, event_type]
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
