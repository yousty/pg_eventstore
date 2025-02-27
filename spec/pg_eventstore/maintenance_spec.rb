# frozen_string_literal: true

RSpec.describe PgEventstore::Maintenance do
  let(:instance) { described_class.new(config) }
  let(:config) { PgEventstore.config }

  describe '#delete_stream' do
    subject { instance.delete_stream(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar',  stream_id: '1') }
    let!(:events) do
      events = Array.new(2) { PgEventstore::Event.new }
      PgEventstore.client.append_to_stream(stream, events)
    end

    it 'deletes it' do
      expect { subject }.to change { safe_read(stream).map(&:id) }.from(events.map(&:id)).to([])
    end
    it { is_expected.to eq(true) }
  end
end
