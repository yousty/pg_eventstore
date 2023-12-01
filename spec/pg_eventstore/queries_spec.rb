# frozen_string_literal: true

RSpec.describe PgEventstore::Queries do
  let(:instance) { described_class.new(PgEventstore.connection, serializer, deserializer) }
  let(:serializer) { PgEventstore::EventSerializer.new(middlewares) }
  let(:deserializer) { PgEventstore::PgresultDeserializer.new(middlewares, PgEventstore::EventClassResolver.new) }
  let(:middlewares) { [] }

  describe '#transaction' do
    it 'yields the given block' do
      expect { |blk| instance.transaction(&blk) }.to yield_with_no_args
    end

    context 'when transaction is not started yet' do
      it 'starts it' do
        expect(instance.transaction { PgEventstore.connection.with(&:transaction_status) }).to eq(PG::PQTRANS_INTRANS)
      end
    end

    context 'when another transaction is already started' do
      it 'does not start another one' do
        expect do
          instance.transaction do
            instance.transaction do
              PgEventstore.connection.with { |c| c.exec('select version()') }
            end
          end
        end.not_to output.to_stderr_from_any_process
      end
    end
  end

  describe '#last_stream_event' do
    subject { instance.last_stream_event(stream1) }

    let(:stream1) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '2') }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid) }

    before do
      PgEventstore.client.append_to_stream(stream1, [event1, event2])
      PgEventstore.client.append_to_stream(stream2, event3)
    end

    it 'returns last event of the given stream' do
      aggregate_failures do
        is_expected.to be_a(PgEventstore::Event)
        expect(subject.id).to eq(event2.id)
      end
    end

    context 'when middlewares are given' do
      let(:middlewares) { [DummyMiddleware.new] }

      it 'ignores it' do
        expect(subject.metadata).to eq({})
      end
    end
  end

  describe '#stream_events' do
    # Tests of different options(second argument) are written as a part of Read command testing
    subject { instance.stream_events(stream1, {}) }

    let(:stream1) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '2') }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid) }

    before do
      PgEventstore.client.append_to_stream(stream1, [event1, event2])
      PgEventstore.client.append_to_stream(stream2, event3)
    end

    it 'returns events of the given stream' do
      aggregate_failures do
        is_expected.to be_an(Array)
        is_expected.to all be_a(PgEventstore::Event)
        expect(subject.map(&:id)).to eq([event1.id, event2.id])
      end
    end
  end

  describe '#insert' do
    subject { instance.insert(event) }

    let(:event) do
      PgEventstore::Event.new(type: :foo, data: { foo: :bar }, metadata: { baz: :bar }, stream_revision: 123, **stream)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-str', stream_id: '1') }
    let(:middlewares) { [DummyMiddleware.new] }

    it 'creates new event' do
      expect { subject }.to change { safe_read(stream).count }.by(1)
    end
    it 'returns created event' do
      aggregate_failures do
        expect(subject.id).to be_a(String)
        expect(subject.type).to eq('foo')
        expect(subject.data).to eq('foo' => 'bar')
        expect(subject.metadata).to include('baz' => 'bar')
        expect(subject.stream_revision).to eq(123)
        expect(subject.stream).to eq(stream)
      end
    end
    it 'does not apply middlewares on deserialization' do
      expect(subject.metadata).to include('dummy_secret' => DummyMiddleware::ENCR_SECRET)
    end
  end
end
