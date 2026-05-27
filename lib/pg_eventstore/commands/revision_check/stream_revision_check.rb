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
              expected_revision.revisions.each do |event_type, expected|
                current = current_revision.revisions[event_type] || Event::NON_EXISTING_EVENT_REVISION
                verdict = EventTypeRevisionsComparison.verdict(current, expected, event_type)
                verdicts << verdict if verdict
              end
              if verdicts.any?
                raise WrongExpectedTypesRevisionError.new(
                  revisions: current_revision.revisions,
                  expected_revisions: expected_revision.revisions,
                  stream:,
                  verdicts:
                )
              end
            else
              raise ArgumentError, "Incorrect combination: #{current_revision.inspect} and #{expected_revision.inspect}"
            end
          end
        end
      end
    end
  end
end
