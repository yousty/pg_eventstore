# frozen_string_literal: true

RSpec.describe PgEventstore::Client do
  let(:instance) { described_class.new(config) }
  let(:config) { PgEventstore.config }
  let(:middleware) do
    Class.new do
      include PgEventstore::Middleware

      def initialize(value)
        @value = value
      end

      def serialize(event)
        event.metadata[@value] = "secret-#{@value}"
      end

      def deserialize(event)
        event.metadata[@value] = @value
      end
    end
  end

  before do
    PgEventstore.configure do |config|
      config.middlewares = { foo: middleware.new('foo'), bar: middleware.new('bar'), baz: middleware.new('baz') }
    end
  end

  shared_examples 'read action with frozen arguments' do
    subject do
      instance.public_send(
        read_method, stream.freeze,
        middlewares: [:foo].freeze,
        options: {
          filter: {
            event_types: ['Foo'].freeze,
            streams: [{ context: 'FooCtx', stream_name: 'Foo', stream_id: 'Bar' }.freeze].freeze,
          }.freeze,
          max_count: 1,
          # from_position: 0,
          resolve_link_tos: true,
          direction: 'Forwards',
        }.freeze
      ).flat_map(&:itself)
    end

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'Bar') }
    let!(:event) do
      event = PgEventstore::Event.new(type: 'Foo')
      PgEventstore.client.append_to_stream(stream, event)
    end

    it 'does not raise error' do
      aggregate_failures do
        expect { subject }.not_to raise_error
        expect(subject.map(&:id)).to eq([event.id])
      end
    end
  end

  describe '#append_to_stream' do
    describe 'common behavior' do
      subject { instance.append_to_stream(stream, events_or_event) }

      let(:events_or_event) { PgEventstore::Event.new(type: 'foo') }
      let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }

      context 'when single event is given' do
        it { expect { subject }.to change { safe_read(stream).count }.by(1) }
        it 'returns persisted event' do
          aggregate_failures do
            is_expected.to be_a(PgEventstore::Event)
            expect(subject.type).to eq('foo')
          end
        end
        it 'applies all middlewares' do
          expect(subject.metadata).to eq('foo' => 'secret-foo', 'bar' => 'secret-bar', 'baz' => 'secret-baz')
        end

        context 'when :middlewares argument is given' do
          subject { instance.append_to_stream(stream, events_or_event, middlewares: %i[bar]) }

          it 'applies only provided middlewares' do
            expect(subject.metadata).to eq('bar' => 'secret-bar')
          end
        end
      end

      context 'when array of events is given' do
        let(:events_or_event) { [PgEventstore::Event.new(type: 'foo')] }

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

    describe 'appending with frozen arguments' do
      subject do
        instance.append_to_stream(
          stream.freeze, [event.freeze].freeze,
          options: { expected_revision: :no_stream }.freeze,
          middlewares: [:foo]
        )
      end

      let(:event) { PgEventstore::Event.new(type: 'Foo', id: SecureRandom.uuid.freeze) }
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'Bar') }

      it 'does not raise error' do
        aggregate_failures do
          expect { subject }.not_to raise_error
          expect(subject.map(&:id)).to eq([event.id])
        end
      end
    end
  end

  describe '#read' do
    describe 'common behavior' do
      subject { instance.read(stream) }

      let(:stream1) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '2') }
      let(:stream) { stream1 }

      before do
        PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'foo'))
        PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'bar'))
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

        it 'applies all middlewares' do
          expect(subject.first.metadata).to eq('foo' => 'foo', 'bar' => 'bar', 'baz' => 'baz')
        end

        context 'when :middlewares argument is given' do
          subject { instance.read(stream, middlewares: %i[bar]) }

          it 'applies only provided middlewares' do
            expect(subject.first.metadata).to eq('foo' => 'secret-foo', 'bar' => 'bar', 'baz' => 'secret-baz')
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

    it_behaves_like 'read action with frozen arguments' do
      let(:read_method) { :read }
    end
  end

  describe '#read_paginated' do
    describe 'common behavior' do
      subject { instance.read_paginated(stream).next }

      let(:stream1) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '2') }
      let(:stream) { stream1 }

      before do
        PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'foo'))
        PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'bar'))
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

        it 'applies all middlewares' do
          expect(subject.first.metadata).to eq('foo' => 'foo', 'bar' => 'bar', 'baz' => 'baz')
        end

        context 'when :middlewares argument is given' do
          subject { instance.read(stream, middlewares: %i[bar]) }

          it 'applies only provided middlewares' do
            expect(subject.first.metadata).to eq('foo' => 'secret-foo', 'bar' => 'bar', 'baz' => 'secret-baz')
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

    it_behaves_like 'read action with frozen arguments' do
      let(:read_method) { :read_paginated }
    end
  end

  describe '#read_grouped' do
    describe 'common behavior' do
      subject { instance.read_grouped(stream) }

      let(:stream1) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '2') }
      let(:stream) { stream1 }

      before do
        PgEventstore.client.append_to_stream(stream1, Array.new(2) { PgEventstore::Event.new(type: 'foo') })
        PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'bar'))
      end

      context 'when reading from the specific stream' do
        it 'returns a projection of events of the given stream' do
          aggregate_failures do
            is_expected.to be_an(Array)
            is_expected.to all be_a(PgEventstore::Event)
            expect(subject.size).to eq(1)
            expect(subject.first.type).to eq('foo')
            expect(subject.first.stream).to eq(stream)
          end
        end

        it 'applies all middlewares' do
          expect(subject.first.metadata).to eq('foo' => 'foo', 'bar' => 'bar', 'baz' => 'baz')
        end

        context 'when :middlewares argument is given' do
          subject { instance.read(stream, middlewares: %i[bar]) }

          it 'applies only provided middlewares' do
            expect(subject.first.metadata).to eq('foo' => 'secret-foo', 'bar' => 'bar', 'baz' => 'secret-baz')
          end
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns a projection of all events' do
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

    it_behaves_like 'read action with frozen arguments' do
      let(:read_method) { :read_grouped }
    end
  end

  describe '#multiple' do
    context 'when :read_only arg is not present' do
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
      let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
      let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }

      it 'processes the given commands' do
        subject
        expect(PgEventstore.client.read(PgEventstore::Stream.all_stream).map(&:id)).to eq([event1.id, event2.id])
      end
    end

    context 'when :read_only arg is present' do
      subject { instance.multiple(read_only: read_only) { command } }

      let(:command) do
        stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
      end
      let(:read_only) { false }

      context 'when read_only is false' do
        context 'when command is a write command' do
          it 'performs it' do
            expect { subject }.not_to raise_error
          end
        end

        context 'when command is a read command' do
          let(:command) do
            PgEventstore.client.read(PgEventstore::Stream.all_stream)
          end

          it 'performs it' do
            expect { subject }.not_to raise_error
          end
        end
      end

      context 'when read_only is true' do
        let(:read_only) { true }

        context 'when command is a write command' do
          it 'raises error' do
            expect { subject }.to raise_error(PG::ReadOnlySqlTransaction)
          end
        end

        context 'when command is a read command' do
          let(:command) do
            PgEventstore.client.read(PgEventstore::Stream.all_stream)
          end

          it 'performs it' do
            expect { subject }.not_to raise_error
          end
        end
      end
    end
  end

  describe '#link_to' do
    subject { instance.link_to(projection_stream, events_or_event) }

    let(:persisted_event) { PgEventstore.client.append_to_stream(events_stream, PgEventstore::Event.new(type: 'foo')) }
    let(:events_stream) { PgEventstore::Stream.new(context: 'MyCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:projection_stream) { PgEventstore::Stream.new(context: 'MyCtx', stream_name: 'MyProjection', stream_id: '1') }

    let(:events_or_event) { persisted_event }

    context 'when single event is given' do
      it { expect { subject }.to change { safe_read(projection_stream).count }.by(1) }
      it 'returns persisted link event' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Event)
          expect(subject.type).to eq(PgEventstore::Event::LINK_TYPE)
        end
      end
      it 'does not apply any middlewares' do
        expect(subject.metadata).to eq({})
      end

      context 'when :middlewares argument is given' do
        subject { instance.link_to(projection_stream, events_or_event, middlewares: %i[bar]) }

        it 'applies provided middlewares' do
          expect(subject.metadata).to eq('bar' => 'secret-bar')
        end
      end
    end

    context 'when array of events is given' do
      let(:events_or_event) { [persisted_event] }

      it 'returns an array of persisted link events' do
        aggregate_failures do
          is_expected.to be_an(Array)
          is_expected.to all be_a(PgEventstore::Event)
          expect(subject.size).to eq(1)
          expect(subject.first.type).to eq(PgEventstore::Event::LINK_TYPE)
        end
      end
    end
  end
end
