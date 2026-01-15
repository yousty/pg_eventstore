# frozen_string_literal: true

RSpec.describe PgEventstore::MaintenanceQueries do
  let(:instance) { described_class.new(connection) }
  let(:connection) { PgEventstore.connection }

  describe '#delete_stream' do
    subject { instance.delete_stream(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

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
      let(:another_stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2') }
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

  describe '#delete_event' do
    subject { instance.delete_event(event) }

    let(:event) { PgEventstore::Event.new(stream:) }
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

    context 'when event exists' do
      let!(:event) do
        event = PgEventstore::Event.new
        PgEventstore.client.append_to_stream(stream, event)
      end

      it 'deletes it' do
        expect { subject }.to change { safe_read(stream).map(&:id) }.to([])
      end
      it 'returns the number of deleted events' do
        is_expected.to eq(1)
      end
    end

    context 'when event does not exist' do
      let!(:events) do
        events = Array.new(2) { PgEventstore::Event.new }
        PgEventstore.client.append_to_stream(stream, events)
      end

      it 'returns the number of deleted events' do
        is_expected.to eq(0)
      end
      it 'does not delete another events' do
        expect { subject }.not_to change { safe_read(stream).map(&:id) }.from(events.map(&:id))
      end
    end
  end

  describe '#adjust_stream_revisions' do
    subject { instance.adjust_stream_revisions(stream, after_revision) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
    let(:events) do
      PgEventstore.client.append_to_stream(stream, Array.new(4) { PgEventstore::Event.new })
    end
    let(:after_revision) { 1 }

    before do
      instance.delete_event(events[after_revision])
    end

    it 'adjusts stream revisions' do
      expect { subject }.to change { safe_read(stream).map(&:stream_revision) }.from([0, 2, 3]).to([0, 1, 2])
    end
  end

  describe '#events_to_lock_count' do
    subject { instance.events_to_lock_count(stream, after_revision) }

    let!(:events) do
      PgEventstore.client.append_to_stream(stream, Array.new(4) { PgEventstore::Event.new })
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
    let(:after_revision) { 1 }

    it 'returns an approximate amount of events in the given stream after the given revision' do
      is_expected.to be_between(1, 2)
    end
  end

  describe '#reload_event' do
    subject { instance.reload_event(event) }

    let(:event) { PgEventstore::Event.new }

    context 'when event exists' do
      let(:event) do
        event = PgEventstore::Event.new
        event = PgEventstore.client.append_to_stream(stream, event)
        # Use custom class and custom stream_revision to show that an event attributes are grabbed from the db and the
        # default event class is used to deserialize those attributes
        event_class.new(**event.options_hash, stream_revision: 10)
      end
      let(:event_class) { Class.new(PgEventstore::Event) }
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      it 'reloads it from the database' do
        aggregate_failures do
          expect(subject.id).to eq(event.id)
          expect(subject.stream_revision).to eq(0)
          expect(subject.class).to eq(PgEventstore::Event)
        end
      end
      it 'does not change original event instance' do
        subject
        aggregate_failures do
          expect(event.class).to eq(event_class)
          expect(event.stream_revision).to eq(10)
        end
      end
    end

    context 'when event does not exist' do
      it { is_expected.to eq(nil) }
    end
  end
end
