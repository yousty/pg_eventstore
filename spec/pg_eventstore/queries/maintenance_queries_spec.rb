# frozen_string_literal: true

RSpec.describe PgEventstore::MaintenanceQueries do
  let(:instance) { described_class.new(connection) }
  let(:connection) { PgEventstore.connection }

  describe '#delete_stream' do
    subject { instance.delete_stream(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar',  stream_id: '1') }

    context 'when stream exists' do
      let!(:events) do
        events = Array.new(2) { PgEventstore::Event.new }
        PgEventstore.client.append_to_stream(stream, events)
      end

      it 'deletes it' do
        expect { subject }.to change { safe_read(stream).map(&:id) }.from(events.map(&:id)).to([])
      end
      it 'returns the number of deleted events' do
        is_expected.to eq(2)
      end
    end

    context 'when stream does not exist' do
      let(:another_stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar',  stream_id: '2') }
      let!(:events) do
        events = Array.new(2) { PgEventstore::Event.new }
        PgEventstore.client.append_to_stream(another_stream, events)
      end

      it 'returns the number of deleted events' do
        is_expected.to eq(0)
      end
      it 'does not delete another stream' do
        expect { subject }.not_to change { safe_read(another_stream).map(&:id) }.from(events.map(&:id))
      end
    end
  end
end
