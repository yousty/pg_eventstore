# frozen_string_literal: true

RSpec.describe PgEventstore::Maintenance do
  let(:instance) { described_class.new(config) }
  let(:config) { PgEventstore.config }

  describe '#delete_stream' do
    subject { instance.delete_stream(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
    let!(:events) do
      events = Array.new(2) { PgEventstore::Event.new }
      PgEventstore.client.append_to_stream(stream, events)
    end

    it 'deletes it' do
      expect { subject }.to change { safe_read(stream).map(&:id) }.from(events.map(&:id)).to([])
    end
    it { is_expected.to eq(true) }
  end

  describe '#delete_event' do
    subject { instance.delete_event(event) }

    let(:event) do
      event = PgEventstore::Event.new(data: { foo: :bar })
      PgEventstore.client.append_to_stream(stream, event)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

    shared_examples 'event gets deleted' do
      it 'deletes it' do
        expect { subject }.to change { safe_read(stream).map(&:id) }.to(rest_events.map(&:id))
      end
      it { is_expected.to eq(true) }
    end

    context 'when "force" flag is false' do
      context 'when events to lock for update is more than MAX_RECORDS_TO_LOCK' do
        let(:another_event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }

        before do
          stub_const('PgEventstore::Commands::DeleteEvent::MAX_RECORDS_TO_LOCK', 0)
          event
          another_event
        end

        it 'raises error' do
          expect { subject }.to raise_error(PgEventstore::TooManyRecordsToLockError, /Too many records/)
        end
      end

      context 'when events to lock for update is less than MAX_RECORDS_TO_LOCK' do
        let(:another_event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }

        before do
          event
          another_event
        end

        it_behaves_like 'event gets deleted' do
          let(:rest_events) { [another_event] }
        end
      end
    end

    context 'when "force" flag is true' do
      subject { instance.delete_event(event, force: true) }

      context 'when events to lock for update is more than MAX_RECORDS_TO_LOCK' do
        let(:another_event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }

        before do
          stub_const("#{described_class}::MAX_RECORDS_TO_LOCK", 0)
          event
          another_event
        end

        it_behaves_like 'event gets deleted' do
          let(:rest_events) { [another_event] }
        end
      end

      context 'when events to lock for update is less than MAX_RECORDS_TO_LOCK' do
        let(:another_event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }

        before do
          event
          another_event
        end

        it_behaves_like 'event gets deleted' do
          let(:rest_events) { [another_event] }
        end
      end
    end
  end
end
