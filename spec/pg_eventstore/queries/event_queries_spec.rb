# frozen_string_literal: true

RSpec.describe PgEventstore::EventQueries do
  let(:instance) { described_class.new(PgEventstore.connection, serializer, deserializer) }
  let(:serializer) { PgEventstore::EventSerializer.new(middlewares) }
  let(:deserializer) { PgEventstore::EventDeserializer.new(middlewares, PgEventstore::EventClassResolver.new) }
  let(:middlewares) { [] }

  describe '#stream_revision' do
    subject { instance.stream_revision(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }

    context 'when there are no events for the given stream' do
      it { is_expected.to eq(nil) }
    end

    context 'when there are events for the given stream' do
      let(:event) { PgEventstore::Event.new(type: 'Foo') }

      before do
        PgEventstore.client.append_to_stream(stream, [event, event])
      end

      it 'returns latest revision' do
        is_expected.to eq(1)
      end
    end
  end

  describe '#event_exists?' do
    subject { instance.event_exists?(event_id) }

    let(:event_id) { nil }

    context 'when given id is nil' do
      it { is_expected.to eq(false) }
    end

    context 'when given id is present' do
      let(:event_id) { SecureRandom.uuid }

      context 'when event with the given id exists' do
        let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }

        before do
          PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(id: event_id))
        end

        it { is_expected.to eq(true) }
      end

      context 'when event with the given id does not exist' do
        it { is_expected.to eq(false) }
      end
    end
  end

  describe '#stream_events' do
    # Tests of different options(second argument) are written as a part of Read command testing
    subject { instance.stream_events(stream1, {}) }

    let(:stream1) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '2') }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }

    before do
      PgEventstore.client.append_to_stream(stream1, [event1, event2])
      PgEventstore.client.append_to_stream(stream2, event3)
    end

    it 'returns events of the given stream' do
      aggregate_failures do
        is_expected.to be_an(Array)
        is_expected.to all be_a(PgEventstore::Event)
        expect(subject.map(&:id)).to eq([event1.id, event2.id])
        expect(subject.map(&:type)).to eq(%w[foo bar])
        expect(subject.map(&:stream)).to eq([stream1, stream1])
      end
    end
  end

  describe '#insert' do
    subject { instance.insert(stream, [event]) }

    let(:event) do
      PgEventstore::Event.new(type: 'foo', data: { foo: :bar }, metadata: { baz: :bar }, stream_revision: 123)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-str', stream_id: '1') }
    let(:middlewares) { [DummyMiddleware.new] }
    let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

    before do
      partition_queries.create_partitions(stream, event.type)
    end

    it 'creates new event' do
      expect { subject }.to change { safe_read(stream).count }.by(1)
    end
    it { is_expected.to be_an(Array) }

    describe 'created event' do
      subject { super().first }

      it 'returns created event' do
        aggregate_failures do
          expect(subject.id).to be_a(String)
          expect(subject.type).to eq('foo')
          expect(subject.data).to eq('foo' => 'bar')
          expect(subject.metadata).to include('baz' => 'bar')
          expect(subject.stream_revision).to eq(123)
          expect(subject.link_id).to eq(nil)
          expect(subject.stream).to eq(stream)
          expect(subject.created_at).to be_a(Time)
        end
      end
      it 'does not apply middlewares on deserialization' do
        expect(subject.metadata).to include('dummy_secret' => DummyMiddleware::ENCR_SECRET)
      end
    end

    describe 'inserting link' do
      subject { super().first }

      let(:existing_event) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(id: SecureRandom.uuid))
      end
      let(:event) do
        PgEventstore::Event.new(link_id: existing_event.id, stream_revision: 123, type: PgEventstore::Event::LINK_TYPE)
      end

      it 'creates link event' do
        aggregate_failures do
          expect(subject.id).to match(EventHelpers::UUID_REGEXP)
          expect(subject.type).to eq(PgEventstore::Event::LINK_TYPE)
          expect(subject.stream_revision).to eq(123)
          expect(subject.link_id).to eq(existing_event.id)
        end
      end
    end
  end
end
