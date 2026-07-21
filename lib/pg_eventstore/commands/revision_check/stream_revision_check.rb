# frozen_string_literal: true

require_relative 'expected_revision'
require_relative 'current_revision'
require_relative 'event_type_revisions_comparison'
require_relative 'stream_revision_comparison'

module PgEventstore
  module Commands
    module RevisionCheck
      # @!visibility private
      class StreamRevisionCheck
        class << self
          # @param current_revision [CurrentRevision::StreamRevision, CurrentRevision::EventTypeRevisions, nil]
          # @param expected_revision [ExpectedRevision::StreamRevision, ExpectedRevision::EventTypeRevisions, nil]
          # @param stream [PgEventstore::Stream]
          # @return [void]
          def assert_eq!(current_revision, expected_revision, stream)
            case [current_revision, expected_revision]
            in [_, NilClass]
              # do nothing. We don't have expected revision
            in [CurrentRevision::StreamRevision, ExpectedRevision::StreamRevision]
              verdict = StreamRevisionComparison.verdict(current_revision.revision, expected_revision.revision)
              if verdict
                raise WrongExpectedRevisionError.new(
                  revision: current_revision.revision,
                  expected_revision: expected_revision.revision,
                  stream:,
                  verdict:
                )
              end
            in [CurrentRevision::EventTypeRevisions, ExpectedRevision::EventTypeRevisions]
              verdicts = []
              rev_check_indexes = current_revision.revisions.to_h { [_1.sequence_number, _1] }
              expected_revision.revisions.each do |revision|
                index = find_index(revision, rev_check_indexes)
                verdict =
                  case revision
                  when ExpectedRevision::EventTypeRevision
                    EventTypeRevisionsComparison.verdict(
                      index.stream_revision,
                      revision.expected_revision,
                      event_type: revision.event_type
                    )
                  when ExpectedRevision::EventTypeRevisionWithMarkers
                    EventTypeRevisionsComparison.verdict(
                      index.stream_revision,
                      revision.expected_revision,
                      expected_markers: revision.markers,
                      event_type: revision.event_type
                    )
                  when ExpectedRevision::MarkersRevision
                    EventTypeRevisionsComparison.verdict(
                      index.stream_revision,
                      revision.expected_revision,
                      expected_markers: revision.markers
                    )
                  else
                    Utils.missing_implementation!(revision)
                  end
                verdicts.push(verdict) if verdict
              end
              raise WrongExpectedTypesRevisionError.new(stream:, verdicts:) if verdicts.any?
            else
              Utils.missing_implementation!([current_revision, expected_revision])
            end
          end

          private

          # @param expected_revision [ExpectedRevision::EventTypeRevision,
          #   ExpectedRevision::EventTypeRevisionWithMarkers, ExpectedRevision::MarkersRevision]
          # @param rev_check_indexes [Hash<Integer, PgEventstore::EventGlobalIndex::RevisionCheckRepr>]
          # @return [PgEventstore::EventGlobalIndex::RevisionCheckRepr]
          def find_index(expected_revision, rev_check_indexes)
            from_dictionary = rev_check_indexes[expected_revision.sequence_number]
            return from_dictionary if from_dictionary

            case expected_revision
            when ExpectedRevision::EventTypeRevision
              EventGlobalIndex::RevisionCheckRepr.new(
                sequence_number: expected_revision.sequence_number, stream_revision: Event::NON_EXISTING_EVENT_REVISION
              )
            when ExpectedRevision::EventTypeRevisionWithMarkers, ExpectedRevision::MarkersRevision
              EventGlobalIndex::RevisionCheckRepr.new(
                sequence_number: expected_revision.sequence_number,
                stream_revision: Event::NON_EXISTING_EVENT_REVISION,
                marker: Event::SYSTEM_SYMBOL
              )
            else
              Utils.missing_implementation!(expected_revision)
            end
          end
        end
      end
    end
  end
end
