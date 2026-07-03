# frozen_string_literal: true

RSpec.describe PgEventstore::EventMarkerQueries do
  let(:instance) { described_class.new(PgEventstore.connection, query_strategy) }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

  describe '#find_or_create_by' do
    subject { instance.find_or_create_by(names) }

    let(:names) { %w[Foo Bar] }

    before do
      query_strategy.exec("select setval('event_markers_id_seq'::regclass, 1, false)")
    end

    context 'when some marker does not exist' do
      before do
        instance.find_or_create_by(['Bar'])
      end

      it 'creates another one' do
        expect { subject }.to change {
          query_strategy.exec('select count(*) as c_all from event_markers').first['c_all']
        }.by(1)
      end
      it 'returns both markers' do
        is_expected.to(
          eq(
            [
              PgEventstore::EventMarker.new(id: 1, name: 'Bar'),
              PgEventstore::EventMarker.new(id: 2, name: 'Foo'),
            ]
          )
        )
      end
    end

    context 'when no markers exist' do
      it 'creates both markers' do
        expect { subject }.to change {
          query_strategy.exec('select count(*) as c_all from event_markers').first['c_all']
        }.by(2)
      end
      it 'returns both markers' do
        is_expected.to(
          eq(
            [
              PgEventstore::EventMarker.new(id: 1, name: 'Foo'),
              PgEventstore::EventMarker.new(id: 2, name: 'Bar'),
            ]
          )
        )
      end
    end

    context 'when all markers exist' do
      before do
        instance.find_or_create_by(%w[Foo Bar])
      end

      it 'does not create any markers' do
        expect { subject }.not_to change {
          query_strategy.exec('select count(*) as c_all from event_markers').first['c_all']
        }
      end
      it 'existing markers' do
        is_expected.to(
          eq(
            [
              PgEventstore::EventMarker.new(id: 1, name: 'Foo'),
              PgEventstore::EventMarker.new(id: 2, name: 'Bar'),
            ]
          )
        )
      end
    end
  end

  describe '#create_indexes' do
    subject { instance.create_indexes(stream_idx_id, write_api_events_index, revision_to_marker_ids_map) }

    let(:stream_idx_id) { 1 }
    let(:write_api_idx1) do
      PgEventstore::EventGlobalIndex::WriteApiRepr.new(
        global_position: 1,
        event_type_partition_id: 2,
        stream_revision: 2
      )
    end
    let(:write_api_idx2) do
      PgEventstore::EventGlobalIndex::WriteApiRepr.new(
        global_position: 2,
        event_type_partition_id: 4,
        stream_revision: 3
      )
    end
    let(:write_api_events_index) { [write_api_idx1, write_api_idx2] }
    let(:revision_to_marker_ids_map) do
      { write_api_idx1.stream_revision => [10], write_api_idx2.stream_revision => [10, 20] }
    end

    it 'creates marker indexes' do
      expect { subject }.to change {
        query_strategy.exec('select count(*) as c_all from event_markers_index').first['c_all']
      }.by(3)
    end

    describe 'created indexes' do
      let(:created_indexes) do
        query_strategy.exec('select * from event_markers_index').to_a
      end

      before do
        subject
      end

      it 'has correct attributes' do
        expect(created_indexes).to(
          match_array(
            [
              {
                'marker_id' => 10,
                'streams_global_index_id' => stream_idx_id ,
                'global_position' => write_api_idx1.global_position,
                'stream_revision' => write_api_idx1.stream_revision,
                'event_type_partition_id' => write_api_idx1.event_type_partition_id,
              },
              {
                'marker_id' => 10,
                'streams_global_index_id' => stream_idx_id,
                'global_position' => write_api_idx2.global_position,
                'stream_revision' => write_api_idx2.stream_revision,
                'event_type_partition_id' => write_api_idx2.event_type_partition_id,
              },
              {
                'marker_id' => 20,
                'streams_global_index_id' => stream_idx_id,
                'global_position' => write_api_idx2.global_position,
                'stream_revision' => write_api_idx2.stream_revision,
                'event_type_partition_id' => write_api_idx2.event_type_partition_id,
              },
            ]
          )
        )
      end
    end
  end
end
