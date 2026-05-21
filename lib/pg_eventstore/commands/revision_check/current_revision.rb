# frozen_string_literal: true

module PgEventstore
  module Commands
    module RevisionCheck
      class CurrentRevision
        StreamRevision = Struct.new(:revision)
        EventTypeRevisions = Struct.new(:revisions)

        class << self
          def build(stream, stream_revision, expected_revision, partitions, events_global_index_queries)
            case expected_revision
            in ExpectedRevision::StreamRevision
              StreamRevision.new(revision: stream_revision)
            in ExpectedRevision::EventTypeRevisions
              revisions = current_revision_by_event_types(
                stream, expected_revision.revisions.keys, partitions, events_global_index_queries
              )
              EventTypeRevisions.new(revisions:)
            in NilClass
              # do nothing
            else
              raise ArgumentError
            end
          end

          private

          def current_revision_by_event_types(stream, event_types, affected_partitions, events_global_idx_queries)
            affected_partitions = affected_partitions.to_h { [_1.id, _1.event_type] }
            filters_collection = QueryBuilders::Filters::Collection.from_stream_and_options(
              stream, { filter: { event_types: } }
            )
            cursor = QueryBuilders::ReadCursor::StreamCursor.from_stream_and_options(stream, { direction: :desc })
            indexes = events_global_idx_queries.fetch_indexes_for_revision_validation(filters_collection, cursor)
            indexes.to_h do |event_global_index|
              event_type = affected_partitions[event_global_index.event_type_partition_id]
              [event_type, event_global_index.stream_revision]
            end
          end
        end
      end
    end
  end
end
