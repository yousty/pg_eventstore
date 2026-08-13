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

  let(:read_only_middleware) do
    Class.new(middleware) do
      def deserialize_on_append?
        false
      end
    end
  end
  let(:plain_object_middleware) do
    Class.new do
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
          expect(subject.metadata).to eq('foo' => 'foo', 'bar' => 'bar', 'baz' => 'baz')
        end

        context 'when :middlewares argument is given' do
          subject { instance.append_to_stream(stream, events_or_event, middlewares: %i[bar]) }

          it 'applies only provided middlewares' do
            expect(subject.metadata).to eq('bar' => 'bar')
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

    describe 're-appending persisted event' do
      subject { instance.append_to_stream(stream, persisted_event) }

      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:persisted_event) { instance.append_to_stream(stream, PgEventstore::Event.new(markers: ['bar'])) }

      context 'when markers get removed from persisted event' do
        before do
          persisted_event.markers = []
        end

        it 'does not assign any markers to the re-appended event' do
          aggregate_failures do
            expect(subject.markers).to eq([])
            expect(subject.metadata).not_to include(PgEventstore::Event::MARKERS_METADATA_KEY)
          end
        end
      end

      context 'when markers stays from persisted event' do
        it 'assigns markers to the re-appended event' do
          aggregate_failures do
            expect(subject.markers).to eq(['bar'])
            expect(subject.metadata).to include(PgEventstore::Event::MARKERS_METADATA_KEY => ['bar'])
          end
        end
      end
    end

    describe 'deserialization of the appended event' do
      subject { instance.append_to_stream(stream, event) }

      let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
      let(:event) { PgEventstore::Event.new(type: 'foo') }
      let(:persisted_metadata) { instance.read(stream, middlewares: []).last.metadata }

      context 'when a middleware opts out of the deserialization on append' do
        before do
          PgEventstore.configure do |config|
            config.middlewares = { foo: middleware.new('foo'), bar: read_only_middleware.new('bar') }
          end
        end

        it 'skips #deserialize of that middleware' do
          expect(subject.metadata).to eq('foo' => 'foo', 'bar' => 'secret-bar')
        end
        it 'still applies #serialize of that middleware' do
          subject
          expect(persisted_metadata).to eq('foo' => 'secret-foo', 'bar' => 'secret-bar')
        end
        it 'still applies #deserialize of that middleware when reading the event' do
          subject
          expect(instance.read(stream).last.metadata).to eq('foo' => 'foo', 'bar' => 'bar')
        end
      end

      # :rbs_skip - sig/pg_eventstore/config.rbs types middlewares as PgEventstore::Middleware, while a middleware is
      # only required to respond to #serialize/#deserialize. See docs/writing_middleware.md.
      context 'when a middleware does not implement #deserialize_on_append?', :rbs_skip do
        before do
          PgEventstore.configure do |config|
            config.middlewares = { foo: plain_object_middleware.new('foo') }
          end
        end

        it 'applies #deserialize of that middleware' do
          expect(subject.metadata).to eq('foo' => 'foo')
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
      subject { instance.read_grouped(stream, options:) }

      let(:options) { {} }
      let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }

      context 'when :event_types filter is not provided' do
        it 'raises error' do
          expect { subject }.to raise_error(ArgumentError, '#read_grouped requires correct :event_types filter.')
        end
      end

      context 'when :event_types filter is provided' do
        let(:stream1) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '1') }
        let(:stream2) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: '2') }
        let(:stream) { stream1 }
        let(:options) { { filter: { event_types: %w[foo bar] } } }

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
    end

    it_behaves_like 'read action with frozen arguments' do
      let(:read_method) { :read_grouped }
    end
  end

  describe '#read_streams' do
    subject { instance.read_streams(options:) }

    let(:options) { {} }

    context 'when no streams exist' do
      it { is_expected.to eq([]) }
    end

    context 'when some streams exist' do
      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

      before do
        PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
        PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      end

      it { is_expected.to eq([stream1, stream2]) }
    end
  end

  describe '#read_streams_paginated' do
    subject { instance.read_streams_paginated(options:) }

    let(:options) { {} }
    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
    end

    it { is_expected.to be_a(Enumerator) }
    it 'yields existing streams' do
      expect(subject.to_a).to eq([[stream1, stream2]])
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
          expect(subject.metadata).to eq('bar' => 'bar')
        end

        context 'when the provided middleware opts out of the deserialization on append' do
          before do
            PgEventstore.configure do |config|
              config.middlewares = { bar: read_only_middleware.new('bar') }
            end
          end

          it 'skips #deserialize of that middleware' do
            expect(subject.metadata).to eq('bar' => 'secret-bar')
          end
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

  describe '#stream_revision' do
    subject { instance.stream_revision(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    before do
      PgEventstore.client.append_to_stream(stream, [PgEventstore::Event.new] * 2)
    end

    it { is_expected.to eq(1) }
  end
end
