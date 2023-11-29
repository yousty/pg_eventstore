# frozen_string_literal: true

RSpec.describe PgEventstore::Client do
  let(:instance) { described_class.new(config) }
  let(:config) { PgEventstore.config }

  describe '#append_to_stream' do
    subject { instance.append_to_stream(stream, events_or_event) }

    let(:events_or_event) { PgEventstore::Event.new(type: :foo) }
    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }

    context 'when single event is given' do
      it { expect { subject }.to change { safe_read(stream).count }.by(1) }
      it 'returns persisted event' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Event)
          expect(subject.type).to eq('foo')
        end
      end
    end

    context 'when array of events is given' do
      let(:events_or_event) { [PgEventstore::Event.new(type: :foo)] }

      it 'returns an array of persisted events' do
        aggregate_failures do
          is_expected.to be_an(Array)
          is_expected.to all be_a(PgEventstore::Event)
          expect(subject.size).to eq(1)
          expect(subject.first.type).to eq('foo')
        end
      end
    end
  end

  describe '#read' do
    subject { instance.read(stream) }

    let(:stream1) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '2') }
    let(:stream) { stream1 }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: :foo))
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: :bar))
    end

    context 'when reading from the specific stream' do
      it 'returns events of the given stream' do
        aggregate_failures do
          is_expected.to be_an(Array)
          is_expected.to all be_a(PgEventstore::Event)
          expect(subject.size).to eq(1)
          expect(subject.first.type).to eq('foo')
          expect(subject.first.stream).to eq(stream)
        end
      end
    end

    context 'when reading from "all" stream' do
      let(:stream) { PgEventstore::Stream.all_stream }

      it 'returns all events' do
        aggregate_failures do
          is_expected.to be_an(Array)
          is_expected.to all be_a(PgEventstore::Event)
          expect(subject.size).to eq(2)
          expect(subject.first.type).to eq('foo')
          expect(subject.last.type).to eq('bar')
          expect(subject.first.stream).to eq(stream1)
          expect(subject.last.stream).to eq(stream2)
        end
      end
    end
  end

  describe '#multiple' do
    subject do
      instance.multiple do
        PgEventstore.client.append_to_stream(events_stream1, event1)
        PgEventstore.client.append_to_stream(events_stream2, event2)
      end
    end

    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: '1234')
    end
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }

    it 'processes the given commands' do
      subject
      expect(PgEventstore.client.read(PgEventstore::Stream.all_stream).map(&:id)).to eq([event1.id, event2.id])
    end
  end
end
