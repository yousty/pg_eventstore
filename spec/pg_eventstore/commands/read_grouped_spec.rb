# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::ReadGrouped do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(
      events_global_index: events_global_index_queries,
      streams_global_index: streams_global_index_queries
    )
  end
  let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }
  let(:events_global_index_queries) do
    PgEventstore::EventsGlobalIndexQueries.new(
      PgEventstore.connection, PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection)
    )
  end
  let(:streams_global_index_queries) do
    PgEventstore::StreamsGlobalIndexQueries.new(
      PgEventstore.connection, PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection)
    )
  end
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }
  let(:deserializer) { PgEventstore::EventDeserializer.new(middlewares, event_class_resolver) }

  describe '#call' do
    context 'when reading from existing stream' do
      subject { instance.call(stream1, options:, deserializer:) }

      let(:options) { {} }

      let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }
      let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Baz') }
      let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

      before do
        # Append events in non-sequential order to simulate real events distribution
        PgEventstore.client.append_to_stream(stream1, [event1, event2])
        PgEventstore.client.append_to_stream(stream2, event3)
        PgEventstore.client.append_to_stream(stream1, event4)
      end

      context 'when :event_types filter is provided' do
        let(:options) { { filter: { event_types: %w[Foo Bar Baz] } } }

        context 'when :direction is "Forwards"' do
          it 'returns a projection of the oldest events' do
            expect(subject.map(&:id)).to eq([event1.id, event2.id])
          end

          context 'when :from_revision option is given' do
            before do
              options[:from_revision] = 1
            end

            it 'returns a projection of the oldest events from the given revision' do
              expect(subject.map(&:id)).to eq([event2.id, event4.id])
            end
          end

          context 'when :to_revision option is given' do
            before do
              options[:to_revision] = 1
            end

            it 'returns a projection of the oldest events to the given revision' do
              expect(subject.map(&:id)).to eq([event1.id, event2.id])
            end
          end
        end

        context 'when :direction is "Backwards"' do
          before do
            options[:direction] = 'Backwards'
          end

          it 'returns a projection of the newest events' do
            expect(subject.map(&:id)).to eq([event4.id, event2.id])
          end

          context 'when :from_revision option is given' do
            before do
              options[:from_revision] = 1
            end

            it 'returns a projection of the newest events from the given revision' do
              expect(subject.map(&:id)).to eq([event2.id, event1.id])
            end
          end

          context 'when :to_revision option is given' do
            before do
              options[:to_revision] = 1
            end

            it 'returns a projection of the newest events to the given revision' do
              expect(subject.map(&:id)).to eq([event4.id, event2.id])
            end
          end
        end

        context 'when filtering by one event type' do
          let(:options) { { filter: { event_types: ['Foo'] } } }

          it 'returns a projection of the given event types' do
            expect(subject.map(&:id)).to eq([event1.id])
          end
        end
      end

      context 'when :event_types filter is not provided' do
        it 'raises error' do
          expect { subject }.to raise_error(ArgumentError, '#read_grouped requires :event_types filter.')
        end
      end

      context 'when prefix :event_types filter is provided' do
        let(:options) { { filter: { event_types: [{ prefix: 'Foo' }] } } }

        it 'raises error' do
          expect { subject }.to(
            raise_error(PgEventstore::NotSupportedError, '#read_grouped does not support look up by prefix.')
          )
        end
      end
    end

    context 'when reading from "all" stream' do
      subject { instance.call(PgEventstore::Stream.all_stream, options:, deserializer:) }

      let(:options) { {} }

      let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }
      let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Baz') }
      let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

      before do
        # Append events in non-sequential order to simulate real events distribution
        PgEventstore.client.append_to_stream(stream1, [event1, event2])
        PgEventstore.client.append_to_stream(stream2, event3)
        PgEventstore.client.append_to_stream(stream1, event4)
      end

      context 'when :event_types filter is provided' do
        let(:options) { { filter: { event_types: %w[Foo Bar] } } }

        context 'when :direction is "Forwards"' do
          it 'returns a projection of the oldest events' do
            expect(subject.map(&:id)).to eq([event1.id, event2.id])
          end

          context 'when :from_position option is given' do
            before do
              options[:from_position] = safe_read(PgEventstore::Stream.all_stream)[1].global_position
            end

            it 'returns a projection of the oldest events from the given position' do
              expect(subject.map(&:id)).to eq([event2.id, event4.id])
            end
          end

          context 'when :to_position option is given' do
            before do
              options[:to_position] = safe_read(PgEventstore::Stream.all_stream)[2].global_position
            end

            it 'returns a projection of the oldest events to the given position' do
              expect(subject.map(&:id)).to eq([event1.id, event2.id])
            end
          end
        end

        context 'when :direction is "Backwards"' do
          before do
            options[:direction] = 'Backwards'
          end

          it 'returns a projection of the newest events' do
            expect(subject.map(&:id)).to eq([event4.id, event2.id])
          end

          context 'when :from_position option is given' do
            before do
              options[:from_position] = safe_read(PgEventstore::Stream.all_stream)[1].global_position
            end

            it 'returns a projection of the newest events from the given position' do
              expect(subject.map(&:id)).to eq([event2.id, event1.id])
            end
          end

          context 'when :to_position option is given' do
            before do
              options[:to_position] = safe_read(PgEventstore::Stream.all_stream)[2].global_position
            end

            it 'returns a projection of the newest events to the given position' do
              expect(subject.map(&:id)).to eq([event4.id])
            end
          end
        end

        context 'when filtering by one event type' do
          let(:options) { { filter: { event_types: ['Foo'] } } }

          it 'returns a projection of the given event types' do
            expect(subject.map(&:id)).to eq([event1.id])
          end
        end
      end
    end

    context 'when reading from non-existing stream' do
      subject { instance.call(stream, deserializer:, options: { filter: { event_types: ['Foo'] } }) }

      let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'Foo', stream_id: '1') }

      it 'raises error' do
        expect { subject.to_a }.to raise_error(PgEventstore::StreamNotFoundError)
      end
    end

    describe 'reading links' do
      subject { instance.call(projection_stream, deserializer:, options:) }

      let(:options) { { filter: { event_types: ['Foo', 'Bar', PgEventstore::Event::LINK_TYPE] } } }

      let(:existing_event1) do
        event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo')
        PgEventstore.client.append_to_stream(stream, event)
      end
      let(:existing_event2) do
        event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar')
        PgEventstore.client.append_to_stream(stream, event)
      end
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      let(:projection_stream) do
        PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyProjection', stream_id: '1')
      end
      let!(:link1) do
        PgEventstore.client.link_to(projection_stream, existing_event1)
      end
      let!(:link2) do
        PgEventstore.client.link_to(projection_stream, existing_event2)
      end

      it 'returns a projection by "link" event type' do
        is_expected.to eq([link1])
      end

      context 'when projection stream contains regular event' do
        let!(:existing_event3) do
          event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar')
          PgEventstore.client.append_to_stream(projection_stream, event)
        end

        it 'includes it into a projection' do
          is_expected.to match_array([link1, existing_event3])
        end
      end

      context 'when :resolve_link_tos is provided' do
        before do
          options[:resolve_link_tos] = true
        end

        it 'returns original events, projected by "link" event type' do
          is_expected.to eq([existing_event1])
        end

        context 'when projection stream contains regular event' do
          let!(:existing_event3) do
            event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar')
            PgEventstore.client.append_to_stream(projection_stream, event)
          end

          it 'includes it into a projection' do
            is_expected.to match_array([existing_event1, existing_event3])
          end
        end
      end
    end

    describe 'middlewares' do
      subject { instance.call(stream, options: { filter: { event_types: %w[Foo Bar] } }, deserializer:) }

      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }

      before do
        PgEventstore.client.append_to_stream(stream, [event1, event2])
      end

      context 'when middleware is present' do
        let(:middlewares) { [DummyMiddleware.new] }

        it 'modifies events using it' do
          expect(subject.map(&:metadata)).to(
            eq(
              [
                { 'dummy_secret' => DummyMiddleware::DECR_SECRET },
                { 'dummy_secret' => DummyMiddleware::DECR_SECRET },
              ]
            )
          )
        end
      end

      context 'when a middleware has default Middleware module implementation' do
        let(:middlewares) { [dummy_middleware.new] }
        let(:dummy_middleware) do
          Class.new.tap { |c| c.include(PgEventstore::Middleware) }
        end

        it 'does not modify events' do
          expect(subject.map(&:metadata)).to eq([{}, {}])
        end
      end
    end
  end

  describe 'resolves event class when reading from stream' do
    subject { instance.call(stream, deserializer:, options:) }

    let(:event_class) { Class.new(PgEventstore::Event) }
    let(:event) { event_class.new }
    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
    let(:options) { { filter: { event_types: ['DummyClass'] } } }

    before do
      stub_const('DummyClass', event_class)
      PgEventstore.client.append_to_stream(stream, event)
    end

    it "recognizes event's class" do
      expect(subject.first).to be_a(DummyClass)
    end

    context 'when :resolve_link_tos option is given' do
      before do
        options[:resolve_link_tos] = true
      end

      it "recognizes event's class" do
        expect(subject.first).to be_a(DummyClass)
      end
    end
  end

  describe 'general read cases' do
    let(:stream1) do
      PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
    end
    let(:stream2) do
      PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2')
    end
    let(:stream3) do
      PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1')
    end

    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Baz') }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
    let(:event6) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
    let(:event7) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }

    before do
      PgEventstore.client.append_to_stream(stream1, [event1, event2])
      PgEventstore.client.append_to_stream(stream2, [event3, event4, event5, event6])
      PgEventstore.client.append_to_stream(stream3, event7)
    end

    context 'when reading a mix of existing and non-existing event type filters' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:) }

      let(:options) { { filter: { event_types: %w[NonExisting Baz] } } }

      it 'returns events for the existing part' do
        expect(subject.map(&:id)).to eq([event3.id])
      end
    end

    context 'when reading a mix of existing and non-existing event type and stream filters' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:) }

      let(:options) do
        {
          filter: {
            streams: [{ context: 'FooCtx', stream_name: 'NonExisting1' }, stream2.to_hash],
            event_types: %w[NonExisting2 Foo],
          },
        }
      end

      it 'returns events for the existing part' do
        expect(subject.map(&:id)).to eq([event5.id])
      end
    end

    context 'when combining :from_position, :to_position and :direction' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:) }

      let(:options) { { filter: { event_types: %w[Foo Bar Baz] }, **cursor_options } }
      let(:cursor_options) { {} }

      describe 'ascending order' do
        let(:cursor_options) { { from_position:, to_position: } }
        let(:from_position) { safe_read(stream2).first.global_position }
        let(:to_position) { safe_read(stream3).first.global_position }

        it 'returns events according to those restrictions' do
          expect(subject.map(&:id)).to eq([event3.id, event4.id, event5.id, event7.id])
        end
      end

      describe 'descending order' do
        let(:cursor_options) { { from_position:, to_position:, direction: :desc } }
        let(:from_position) { safe_read(stream3).first.global_position }
        let(:to_position) { safe_read(stream2).first.global_position }

        it 'returns events according to those restrictions' do
          expect(subject.map(&:id)).to eq([event7.id, event6.id, event4.id, event3.id])
        end
      end
    end

    context 'when combining :from_revision, :to_revision and :direction' do
      subject { instance.call(stream2, deserializer:, options:) }

      let(:options) { { filter: { event_types: %w[Foo Bar Baz] }, **cursor_options } }
      let(:cursor_options) { {} }

      describe 'ascending order' do
        let(:cursor_options) { { from_revision: 0, to_revision: 2 } }

        it 'returns events according to those restrictions' do
          expect(subject.map(&:id)).to eq([event3.id, event4.id, event5.id])
        end
      end

      describe 'descending order' do
        let(:cursor_options) { { from_revision: 2, to_revision: 0, direction: :desc } }

        it 'returns events according to those restrictions' do
          expect(subject.map(&:id)).to eq([event5.id, event4.id, event3.id])
        end
      end
    end
  end
end
