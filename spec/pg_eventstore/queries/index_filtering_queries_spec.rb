# frozen_string_literal: true

RSpec.describe PgEventstore::IndexFilteringQueries do
  let(:instance) { described_class.new(PgEventstore.connection, query_strategy) }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

  describe '#fetch_indexes_for_revision_validation' do
    subject { instance.fetch_indexes_for_revision_validation(stream, expected_revisions) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:expected_revisions) { [] }

    describe 'indexes for event type expected revisions' do
      let(:expected_revision1) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevision.new(
          expected_revision: 0,
          event_type: 'Foo',
          sequence_number: 0
        )
      end
      let(:expected_revision2) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevision.new(
          expected_revision: 0,
          event_type: 'Bar',
          sequence_number: 1
        )
      end
      let(:expected_revisions) { [expected_revision1, expected_revision2] }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', markers: ['foo']) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', markers: ['bar']) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', markers: ['baz']) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', markers: ['baz']) }
      let(:unmatched_event) { PgEventstore::Event.new(type: 'Baz', markers: ['baz']) }

      before do
        PgEventstore.client.append_to_stream(stream, [event1, unmatched_event, event2, event3, event4])
      end

      it 'returns indexes with latest revisions of related events' do
        is_expected.to(
          eq(
            [
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 3,
                sequence_number: 0
              ),
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 4,
                sequence_number: 1
              ),
            ]
          )
        )
      end
    end

    describe 'indexes for event type with markers expected revisions' do
      let(:expected_revision1) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevisionWithMarkers.new(
          expected_revision: 0,
          event_type: 'Foo',
          markers: ['foo'],
          sequence_number: 0
        )
      end
      let(:expected_revision2) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevisionWithMarkers.new(
          expected_revision: 0,
          event_type: 'Bar',
          markers: %w[bar baz],
          sequence_number: 1
        )
      end
      let(:expected_revisions) { [expected_revision1, expected_revision2] }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', markers: ['foo']) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', markers: ['bar']) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', markers: ['baz']) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', markers: ['baz']) }
      let(:unmatched_event) { PgEventstore::Event.new(type: 'Baz', markers: ['baz']) }

      before do
        PgEventstore.client.append_to_stream(stream, [event1, unmatched_event, event2, event3, event4])
      end

      it 'returns indexes with latest revisions of related events' do
        is_expected.to(
          eq(
            [
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 0,
                sequence_number: 0
              ),
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 4,
                sequence_number: 1
              ),
            ]
          )
        )
      end
    end

    describe 'indexes for markers expected revisions' do
      let(:expected_revision1) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::MarkersRevision.new(
          expected_revision: 0,
          markers: ['foo'],
          sequence_number: 0
        )
      end
      let(:expected_revision2) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::MarkersRevision.new(
          expected_revision: 0,
          markers: %w[bar baz],
          sequence_number: 1
        )
      end
      let(:expected_revisions) { [expected_revision1, expected_revision2] }

      let(:event1) { PgEventstore::Event.new(type: 'FooBar', markers: ['foo']) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', markers: ['bar']) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', markers: ['baz']) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', markers: ['baz']) }
      let(:unmatched_event) { PgEventstore::Event.new(type: 'Baz', markers: ['baz']) }

      before do
        PgEventstore.client.append_to_stream(stream, [event1, unmatched_event, event2, event3, event4])
      end

      it 'returns indexes with latest revisions of related events' do
        is_expected.to(
          eq(
            [
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 0,
                sequence_number: 0
              ),
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 4,
                sequence_number: 1
              ),
            ]
          )
        )
      end
    end

    describe 'mix of different expected revisions' do
      let(:expected_revision1) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevision.new(
          expected_revision: 0,
          event_type: 'Foo',
          sequence_number: 0
        )
      end
      let(:expected_revision2) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevisionWithMarkers.new(
          expected_revision: 0,
          event_type: 'Bar',
          markers: ['foo'],
          sequence_number: 1
        )
      end
      let(:expected_revision3) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::MarkersRevision.new(
          expected_revision: 0,
          markers: ['foo'],
          sequence_number: 2
        )
      end
      let(:expected_revision4) do
        PgEventstore::Commands::RevisionCheck::ExpectedRevision::EventTypeRevision.new(
          expected_revision: 0,
          event_type: 'Baz',
          sequence_number: 3
        )
      end
      let(:expected_revisions) { [expected_revision1, expected_revision2, expected_revision3, expected_revision4] }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', markers: ['foo']) }
      let(:event2) { PgEventstore::Event.new(type: 'Foo', markers: ['foo']) }
      let(:event3) { PgEventstore::Event.new(type: 'Bar', markers: ['foo']) }
      let(:event4) { PgEventstore::Event.new(type: 'Baz', markers: ['foo']) }
      let(:event5) { PgEventstore::Event.new(type: 'Baz', markers: ['bar']) }
      let(:event6) { PgEventstore::Event.new(type: 'Bar', markers: %w[foo bar]) }

      before do
        PgEventstore.client.append_to_stream(stream, [event1, event2, event3, event4, event5, event6])
      end

      it 'returns indexes with latest revisions of related events' do
        is_expected.to(
          eq(
            [
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 1,
                sequence_number: 0
              ),
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 5,
                sequence_number: 1
              ),
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 5,
                sequence_number: 2
              ),
              PgEventstore::EventGlobalIndex::RevisionCheckRepr.new(
                stream_revision: 4,
                sequence_number: 3
              ),
            ]
          )
        )
      end
    end
  end
end
