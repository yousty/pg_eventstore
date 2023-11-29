# frozen_string_literal: true

RSpec.describe PgEventstore::PgresultDeserializer do
  let(:instance) { described_class.new(middlewares, event_class_resolver) }
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#deserialize' do
    subject { instance.deserialize(pgresult) }

    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
    let(:event) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:pgresult) { PgEventstore.connection.with { |c| c.exec('SELECT * FROM events LIMIT 1') } }

    before do
      PgEventstore.client.append_to_stream(stream, event)
    end

    it 'deserializes the given pgresult' do
      aggregate_failures do
        is_expected.to be_an(Array)
        expect(subject.size).to eq(1)
        expect(subject.first).to be_a(PgEventstore::Event)
      end
    end

    context 'when middlewares are given' do
      let(:middlewares) { [DummyMiddleware.new, another_middleware.new] }
      let(:another_middleware) do
        Class.new do
          def deserialize(event)
            event.metadata['foo'] = 'bar'
          end
        end
      end

      it 'transforms events using those middlewares' do
        expect(subject.first.metadata).to eq('dummy_secret' => DummyMiddleware::DECR_SECRET, 'foo' => 'bar')
      end
    end
  end

  describe '#deserialize_one' do
    subject { instance.deserialize_one(pgresult) }

    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:pgresult) { PgEventstore.connection.with { |c| c.exec('SELECT * FROM events LIMIT 1') } }

    before do
      PgEventstore.client.append_to_stream(stream, [event1, event2])
    end

    context 'when pgresult contains one result' do
      it 'deserializes it' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Event)
          expect(subject.id).to eq(event1.id)
        end
      end
    end

    context 'when pgresult contains more than one result' do
      let(:pgresult) { PgEventstore.connection.with { |c| c.exec('SELECT * FROM events LIMIT 2') } }

      it 'deserializes first one' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Event)
          expect(subject.id).to eq(event1.id)
        end
      end
    end

    context 'when pfresult contains no results' do
      let(:pgresult) { PgEventstore.connection.with { |c| c.exec('SELECT * FROM events LIMIT 0') } }

      it { is_expected.to eq(nil) }
    end

    context 'when middlewares are given' do
      let(:middlewares) { [DummyMiddleware.new, another_middleware.new] }
      let(:another_middleware) do
        Class.new do
          def deserialize(event)
            event.metadata['foo'] = 'bar'
          end
        end
      end

      it 'transforms an event using those middlewares' do
        expect(subject.metadata).to eq('dummy_secret' => DummyMiddleware::DECR_SECRET, 'foo' => 'bar')
      end
    end
  end

  describe '#without_middlewares' do
    subject { instance.without_middlewares }

    let(:middlewares) { [DummyMiddleware.new] }

    it 'returns new instance without middlewares' do
      aggregate_failures do
        is_expected.to be_a(described_class)
        expect(subject.middlewares).to be_empty
      end
    end
  end
end
