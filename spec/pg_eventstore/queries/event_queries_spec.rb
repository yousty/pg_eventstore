# frozen_string_literal: true

RSpec.describe PgEventstore::EventQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#insert' do
    subject { instance.insert(stream, [event]) }

    let(:event) do
      PgEventstore::Event.new(type: 'foo', data: { foo: :bar }, metadata: { baz: :bar }, stream_revision: 123)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-str', stream_id: '1') }
    let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

    before do
      partition_queries.create_partitions(stream, event.type)
    end

    it 'creates new event' do
      expect { subject }.to change {
        PgEventstore.connection.with do |conn|
          conn.exec('select count(*) as c_all from events')
        end.first['c_all']
      }.by(1)
    end
    it { is_expected.to be_an(Array) }

    describe 'created event' do
      subject { super().first }

      it 'returns created event' do
        aggregate_failures do
          expect(subject['id']).to be_a(String)
          expect(subject['type']).to eq('foo')
          expect(subject['data']).to eq('foo' => 'bar')
          expect(subject['metadata']).to include('baz' => 'bar')
          expect(subject['stream_revision']).to eq(123)
          expect(subject['link_global_position']).to eq(nil)
          expect(subject['link_partition_id']).to eq(nil)
          expect(subject['context']).to eq(stream.context)
          expect(subject['stream_name']).to eq(stream.stream_name)
          expect(subject['stream_id']).to eq(stream.stream_id)
          expect(subject['created_at']).to be_a(Time)
        end
      end
    end

    describe 'inserting link' do
      subject { super().first }

      let(:existing_event) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(id: SecureRandom.uuid))
      end
      let(:event) do
        PgEventstore::Event.new(
          link_global_position: existing_event.global_position,
          link_partition_id: partition_queries.event_type_partition(stream, existing_event.type)['id'],
          stream_revision: 123,
          type: PgEventstore::Event::LINK_TYPE
        )
      end

      it 'creates link event' do
        aggregate_failures do
          expect(subject['id']).to be_a(String)
          expect(subject['type']).to eq(PgEventstore::Event::LINK_TYPE)
          expect(subject['stream_revision']).to eq(123)
          expect(subject['link_global_position']).to eq(existing_event.global_position)
          expect(subject['link_partition_id']).to eq(partition_queries.event_type_partition(stream, existing_event.type)['id'])
        end
      end
    end
  end
end
