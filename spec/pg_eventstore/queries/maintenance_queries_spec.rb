# frozen_string_literal: true

RSpec.describe PgEventstore::MaintenanceQueries do
  let(:instance) { described_class.new(connection) }
  let(:connection) { PgEventstore.connection }

  describe '#events_to_lock_count' do
    subject { instance.events_to_lock_count(stream, after_revision) }

    let!(:events) do
      PgEventstore.client.append_to_stream(stream, Array.new(4) { PgEventstore::Event.new })
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
    let(:after_revision) { 1 }

    it 'returns the amount of events in the given stream after the given revision' do
      is_expected.to eq(2)
    end
  end
end
