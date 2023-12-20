# frozen_string_literal: true

RSpec.describe PgEventstore::PgResultDeserializer do
  let(:instance) { described_class.new(middlewares, event_class_resolver) }
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#deserialize' do
    subject { instance.deserialize(pg_result) }

    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
    let(:event) do
      PgEventstore::Event.new(id: SecureRandom.uuid, type: 'some-event', data: { foo: :bar }, metadata: { bar: :baz })
    end
    let(:pg_result) do
      PgEventstore.connection.with do |c|
        c.exec('SELECT events.*, event_types.type as type FROM events JOIN event_types ON event_types.id = events.event_type_id LIMIT 1')
      end
    end

    before do
      PgEventstore.client.append_to_stream(stream, event)
    end

    it 'deserializes the given pg_result' do
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
        expect(subject.first.metadata).to eq('dummy_secret' => DummyMiddleware::DECR_SECRET, 'foo' => 'bar', 'bar' => 'baz')
      end
    end

    describe 'deserialized event' do
      subject { super().first }

      it 'has correct attributes' do
        aggregate_failures do
          expect(subject.stream).to be_nil
          expect(subject.id).to eq(event.id)
          expect(subject.type).to eq('some-event')
          expect(subject.data).to eq('foo' => 'bar')
          expect(subject.metadata).to eq('bar' => 'baz')
          expect(subject.stream_revision).to eq(0)
        end
      end

      context 'when result contains info about stream' do
        let(:pg_result) do
          PgEventstore.connection.with do |c|
            c.exec('SELECT events.*, row_to_json(streams.*) as stream FROM events JOIN streams on streams.id = events.stream_id LIMIT 1')
          end
        end

        it 'includes stream attributes' do
          aggregate_failures do
            expect(subject.stream).to eq(stream)
            expect(subject.stream.id).to be_an(Integer)
          end
        end
      end
    end
  end

  describe '#deserialize_one' do
    subject { instance.deserialize_one(pg_result) }

    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:pg_result) { PgEventstore.connection.with { |c| c.exec('SELECT * FROM events LIMIT 1') } }

    before do
      PgEventstore.client.append_to_stream(stream, [event1, event2])
    end

    context 'when pg_result contains one result' do
      it 'deserializes it' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Event)
          expect(subject.id).to eq(event1.id)
        end
      end
    end

    context 'when pg_result contains more than one result' do
      let(:pg_result) { PgEventstore.connection.with { |c| c.exec('SELECT * FROM events LIMIT 2') } }

      it 'deserializes first one' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Event)
          expect(subject.id).to eq(event1.id)
        end
      end
    end

    context 'when pg_result contains no results' do
      let(:pg_result) { PgEventstore.connection.with { |c| c.exec('SELECT * FROM events LIMIT 0') } }

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
