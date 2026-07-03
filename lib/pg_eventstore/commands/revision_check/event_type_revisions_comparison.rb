# frozen_string_literal: true

module PgEventstore
  module Commands
    module RevisionCheck
      # @!visibility private
      class EventTypeRevisionsComparison
        class << self
          # @param current_revision [Integer]
          # @param expected_revision [Symbol, Integer]
          # @param expected_markers [Array<String>, nil]
          # @param event_type [String, Symbol]
          # @return [PgEventstore::WrongExpectedTypesRevisionError::Verdict, nil]
          def verdict(current_revision, expected_revision, expected_markers: nil, event_type: :any)
            return if expected_revision == :any

            verdict_sym =
              case [current_revision, expected_revision]
              in [Event::NON_EXISTING_EVENT_REVISION, Integer]
                :event_is_absent
              in [Integer, Integer]
                :event_revision_does_not_match unless current_revision == expected_revision
              in [Integer, Symbol]
                if current_revision == Event::NON_EXISTING_EVENT_REVISION && expected_revision == :event_exists
                  :event_is_absent
                elsif current_revision > Event::NON_EXISTING_EVENT_REVISION && expected_revision == :no_event
                  :event_is_present
                end
              else
                Utils.missing_implementation!([current_revision, expected_revision])
              end
            return unless verdict_sym

            WrongExpectedTypesRevisionError::Verdict.new(
              verdict: verdict_sym,
              event_type:,
              current_revision:,
              expected_revision:,
              expected_markers:
            )
          end
        end
      end
    end
  end
end
