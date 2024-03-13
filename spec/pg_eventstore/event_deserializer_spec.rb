# frozen_string_literal: true

RSpec.describe PgEventstore::EventDeserializer do
  let(:instance) { described_class.new(middlewares, event_class_resolver) }
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#deserialize_many' do
    subject { instance.deserialize_many(raw_events) }

    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
    let(:event) do
      PgEventstore::Event.new(id: SecureRandom.uuid, type: 'some-event', data: { foo: :bar }, metadata: { bar: :baz })
    end
    let(:raw_events) do
      PgEventstore.connection.with do |c|
        c.exec('SELECT events.* FROM events LIMIT 1')
      end.to_a
    end

    before do
      PgEventstore.client.append_to_stream(stream, event)
    end

    it 'deserializes raw events' do
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
          expect(subject.id).to eq(event.id)
          expect(subject.stream).to eq(stream)
          expect(subject.type).to eq('some-event')
          expect(subject.data).to eq('foo' => 'bar')
          expect(subject.metadata).to eq('bar' => 'baz')
          expect(subject.stream_revision).to eq(0)
        end
      end
    end
  end

  describe '#deserialize' do
    subject { instance.deserialize(attrs) }

    let(:attrs) do
      { 'id' => 123, 'context' => 'MyAwesomeCtx', 'stream_name' => 'Foo', 'stream_id' => 'Bar', 'type' => 'Foo' }
    end

    shared_examples 'attributes deserialization' do
      it 'deserializes raw attributes into Event class instance' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Event)
          expect(subject.id).to eq(attrs['id'])
          expect(subject.stream).to be_a(PgEventstore::Stream)
          expect(subject.type).to eq('Foo')
          expect(subject.stream.context).to eq('MyAwesomeCtx')
          expect(subject.stream.stream_name).to eq('Foo')
          expect(subject.stream.stream_id).to eq('Bar')
        end
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

      it 'transforms an event using those middlewares' do
        expect(subject.metadata).to eq('dummy_secret' => DummyMiddleware::DECR_SECRET, 'foo' => 'bar')
      end
    end

    context 'when deserializing resolved link event' do
      let(:attrs) do
        super().merge('link' => link_attrs)
      end
      let(:link_attrs) do
        {
          'id' => 124, 'link_id' => 123, 'type' => PgEventstore::Event::LINK_TYPE,
          'context' => 'MyAwesomeCtx', 'stream_name' => 'Bar', 'stream_id' => 'Baz'
        }
      end

      it_behaves_like 'attributes deserialization'
      it 'deserializes link attributes' do
        aggregate_failures do
          expect(subject.link.id).to eq(link_attrs['id'])
          expect(subject.link.link_id).to eq(link_attrs['link_id'])
          expect(subject.link.type).to eq(link_attrs['type'])
          expect(subject.link.stream).to(
            eq(PgEventstore::Stream.new(context: 'MyAwesomeCtx', stream_name: 'Bar', stream_id: 'Baz'))
          )
        end
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
