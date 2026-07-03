# frozen_string_literal: true

module PgEventstore
  module Commands
    module RevisionCheck
      # @!visibility private
      class CurrentRevision
        class StreamRevision
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute revision
          #   @return [Integer]
          attribute(:revision)
        end

        class EventTypeRevisions
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute revisions
          #   @return [Array<PgEventstore::EventsGlobalIndex::RevisionCheckRepr>]
          attribute(:revisions)
        end

        class << self
          # @param stream [PgEventstore::Stream]
          # @param stream_revision [Integer]
          # @param expected_revision [ExpectedRevision::StreamRevision, ExpectedRevision::EventTypeRevisions, nil]
          # @param index_filtering_queries [PgEventstore::IndexFilteringQueries]
          # @return [CurrentRevision::StreamRevision, CurrentRevision::EventTypeRevisions, nil]
          def build(stream, stream_revision, expected_revision, index_filtering_queries)
            case expected_revision
            in ExpectedRevision::StreamRevision
              StreamRevision.new(revision: stream_revision)
            in ExpectedRevision::EventTypeRevisions
              indexes = index_filtering_queries.fetch_indexes_for_revision_validation(
                stream, expected_revision.revisions
              )
              EventTypeRevisions.new(revisions: indexes)
            in NilClass
              # do nothing
            else
              raise ArgumentError, "Unsupported expected revision #{expected_revision.inspect}."
            end
          end
        end
      end
    end
  end
end
