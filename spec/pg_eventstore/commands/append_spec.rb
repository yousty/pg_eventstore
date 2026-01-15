# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::Append do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(events: event_queries, partitions: partition_queries, transactions: transaction_queries)
  end
  let(:transaction_queries) { PgEventstore::TransactionQueries.new(PgEventstore.connection) }
  let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }
  let(:event_queries) do
    PgEventstore::EventQueries.new(
      PgEventstore.connection,
      PgEventstore::EventSerializer.new(middlewares),
      PgEventstore::EventDeserializer.new(middlewares, event_class_resolver)
    )
  end
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#call' do
    let(:stream) { PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyAwesomeStream', stream_id: '123') }

    describe 'appending single event' do
      subject { instance.call(stream, event, options:) }

      let(:event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :bar }) }
      let(:options) { {} }

      shared_examples 'appending the event' do
        it 'appends the given event' do
          expect { subject }.to change { safe_read(stream).count }.by(1)
        end
        it 'returns the appended event' do
          aggregate_failures do
            is_expected.to eq([PgEventstore.client.read(stream).last])
            expect(subject.first.stream_revision).to eq(stream_revision)
          end
        end

        describe 'appended event' do
          subject { super(); PgEventstore.client.read(stream).last }

          it 'has correct attributes' do
            aggregate_failures do
              expect(subject.id).to be_a(String).and match(EventHelpers::UUID_REGEXP)
              expect(subject.global_position).to be_a(Integer)
              expect(subject.stream_revision).to eq(stream_revision)
              expect(subject.stream).to eq(stream)
              expect(subject.type).to eq('MyAwesomeEvent')
              expect(subject.data).to eq('foo' => 'bar')
              expect(subject.metadata).to eq({})
              expect(subject.created_at).to be_between(Time.now - 1, Time.now + 1)
              expect(subject.link_id).to eq(nil)
              expect(subject.link_partition_id).to eq(nil)
            end
          end
        end
      end

      context 'when no options are given' do
        it_behaves_like 'appending the event' do
          let(:stream_revision) { 0 }
        end
      end

      context 'when :expected_revision option is :any' do
        let(:options) { { expected_revision: :any } }
        let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }

        before do
          PgEventstore.client.append_to_stream(stream, another_event)
        end

        it_behaves_like 'appending the event' do
          let(:stream_revision) { 1 }
        end
      end

      context 'when :expected_revision option is :no_stream' do
        let(:options) { { expected_revision: :no_stream } }

        context 'when stream exists' do
          let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }

          before do
            PgEventstore.client.append_to_stream(stream, another_event)
          end

          it 'raises error' do
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedRevisionError,
                "Expected stream #{stream.to_hash.inspect} to be absent, but it actually exists."
              )
            )
          end
        end

        context 'when stream does not exist' do
          it_behaves_like 'appending the event' do
            let(:stream_revision) { 0 }
          end
        end
      end

      context 'when :expected_revision option is :stream_exists' do
        let(:options) { { expected_revision: :stream_exists } }

        context 'when stream exists' do
          let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }

          before do
            PgEventstore.client.append_to_stream(stream, another_event)
          end

          it_behaves_like 'appending the event' do
            let(:stream_revision) { 1 }
          end
        end

        context 'when stream does not exist' do
          it 'raises error' do
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedRevisionError,
                "Expected stream #{stream.to_hash.inspect} to exist, but it doesn't."
              )
            )
          end
        end
      end

      context 'when :expected_revision is a number' do
        let(:options) { { expected_revision: } }
        let(:expected_revision) { 0 }

        context "when expected revision matches stream's revision" do
          let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }

          before do
            PgEventstore.client.append_to_stream(stream, another_event)
          end

          it_behaves_like 'appending the event' do
            let(:stream_revision) { 1 }
          end
        end

        context "when expected revision does not match stream's revision" do
          let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }
          let(:expected_revision) { 1 }

          before do
            PgEventstore.client.append_to_stream(stream, another_event)
          end

          it 'raises error' do
            error_message = <<~TEXT.strip
              #{stream.to_hash.inspect} stream revision #{expected_revision.inspect} is expected, but actual stream \
              revision is 0.
            TEXT
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedRevisionError,
                error_message
              )
            )
          end
        end

        context 'when stream does not exist' do
          it 'raises error' do
            error_message = <<~TEXT.strip
              #{stream.to_hash.inspect} stream revision #{expected_revision.inspect} is expected, but stream does not \
              exist.
            TEXT
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedRevisionError,
                error_message
              )
            )
          end
        end
      end

      context 'when middleware is present' do
        let(:middlewares) { [DummyMiddleware.new] }

        it 'modifies the event using it' do
          expect(subject.first.metadata).to eq('dummy_secret' => DummyMiddleware::ENCR_SECRET)
        end
      end

      context 'when a middleware, inherited from Middleware module is present' do
        let(:middlewares) { [dummy_middleware.new] }
        let(:dummy_middleware) do
          Class.new.tap { |c| c.include(PgEventstore::Middleware) }
        end

        it 'does not modify the event' do
          expect(subject.first.metadata).to eq({})
        end
      end

      shared_examples 'read only attribute' do
        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::Extensions::OptionsExtension::ReadonlyAttributeError,
              /#{attribute.inspect} attribute was marked as read only/
            )
          )
        end
      end

      context 'when middleware which changes #link_id is given' do
        let(:middlewares) { [middleware] }
        let(:middleware) do
          Class.new do
            class << self
              include PgEventstore::Middleware

              def serialize(event)
                event.link_id = SecureRandom.uuid
              end
            end
          end
        end

        it_behaves_like 'read only attribute' do
          let(:attribute) { :link_id }
        end
      end

      context 'when middleware which changes #link_partition_id is given' do
        let(:middlewares) { [middleware] }
        let(:middleware) do
          Class.new do
            class << self
              include PgEventstore::Middleware

              def serialize(event)
                event.link_partition_id = -1
              end
            end
          end
        end

        it_behaves_like 'read only attribute' do
          let(:attribute) { :link_partition_id }
        end
      end

      context 'when middleware which changes #stream_revision is given' do
        let(:middlewares) { [middleware] }
        let(:middleware) do
          Class.new do
            class << self
              include PgEventstore::Middleware

              def serialize(event)
                event.stream_revision = -1
              end
            end
          end
        end

        it_behaves_like 'read only attribute' do
          let(:attribute) { :stream_revision }
        end
      end

      context "when event's class is defined" do
        let(:event_class) { Class.new(PgEventstore::Event) }
        let(:event) { event_class.new }

        before do
          stub_const('DummyClass', event_class)
        end

        it 'recognizes it' do
          expect(subject.first).to be_a(DummyClass)
        end
      end

      context 'when "all" stream is given as a stream to append events' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::SystemStreamError,
              "Can't perform this action with #{stream.inspect} system stream."
            )
          )
        end
      end

      context 'when system stream is given as a stream to append events' do
        let(:stream) { PgEventstore::Stream.new(context: '$et', stream_name: 'SomeEvent', stream_id: '') }

        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::SystemStreamError,
              "Can't perform this action with #{stream.inspect} system stream."
            )
          )
        end
      end
    end

    describe 'appending multiple events' do
      subject { instance.call(stream, event1, event2, options:) }

      let(:event1) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :bar }) }
      let(:event2) { PgEventstore::Event.new(type: 'MyAnotherEvent', data: { foo: :baz }) }
      let(:options) { {} }

      it 'appends the given events' do
        expect { subject }.to change { safe_read(stream).count }.by(2)
      end

      describe 'first appended event' do
        subject { super(); PgEventstore.client.read(stream).first }

        it 'has correct attributes' do
          aggregate_failures do
            expect(subject.global_position).to be_a(Integer)
            expect(subject.stream_revision).to eq(0)
            expect(subject.stream).to eq(stream)
            expect(subject.type).to eq('MyAwesomeEvent')
            expect(subject.data).to eq('foo' => 'bar')
            expect(subject.metadata).to eq({})
            expect(subject.created_at).to be_between(Time.now - 1, Time.now + 1)
            expect(subject.link_id).to eq(nil)
            expect(subject.link_partition_id).to eq(nil)
          end
        end
      end

      describe 'second appended event' do
        subject { super(); PgEventstore.client.read(stream).last }

        it 'has correct attributes' do
          aggregate_failures do
            expect(subject.global_position).to be_a(Integer)
            expect(subject.stream_revision).to eq(1)
            expect(subject.stream).to eq(stream)
            expect(subject.type).to eq('MyAnotherEvent')
            expect(subject.data).to eq('foo' => 'baz')
            expect(subject.metadata).to eq({})
            expect(subject.created_at).to be_between(Time.now - 1, Time.now + 1)
            expect(subject.link_id).to eq(nil)
            expect(subject.link_partition_id).to eq(nil)
          end
        end
      end
    end
  end

  describe 'append command consistency' do
    let(:event1) { PgEventstore::Event.new(data: { foo: :bar }, type: 'some-event') }
    let(:event2) { PgEventstore::Event.new(data: { foo: :baz }, type: 'some-event2') }
    let(:event3) { PgEventstore::Event.new(data: { baz: :bar }, type: 'some-event3') }
    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-stream', stream_id: '123') }
    let(:events_count_mapping) { { 'some-event' => 5, 'some-event2' => 3, 'some-event3' => 2 } }
    let(:iterations_number) { 5 }

    # rubocop:disable RSpec/MultipleExpectations
    it 'checks it' do
      iterations_number.times.flat_map do |i|
        t1 = Thread.new do
          sleep 0.1 + (i / 10.0)
          instance.call(stream, *([event1] * events_count_mapping['some-event']))
        end
        t2 = Thread.new do
          sleep 0.1 + (i / 10.0)
          instance.call(stream, *([event2] * events_count_mapping['some-event2']))
        end
        t3 = Thread.new do
          sleep 0.1 + (i / 10.0)
          instance.call(stream, *([event3] * events_count_mapping['some-event3']))
        end
        [t1, t2, t3]
      end.each(&:join)
      events = PgEventstore.client.read(stream)
      sequences = events.map(&:type).each_with_object([]) do |type, arr|
        arr.last&.last == type ? arr.last.push(type) : arr.push([type])
      end

      total_count = events_count_mapping.values.sum * iterations_number
      expect(events.map(&:stream_revision)).to(
        eq((0...total_count).to_a), "Stream #{stream.inspect} has incorrect revisions sequence!"
      )

      sequences.each do |seq|
        count_mapping = events_count_mapping[seq.first]
        failure_message = <<~TEXT
          Expected the sequence of #{seq.first.inspect} events to have a number of events multiple of \
          #{count_mapping}, but got #{seq.size}. It means some event from another process/thread broke the sequence, \
          and append command is not consistent within the concurrent environment.
        TEXT
        expect(seq.size % count_mapping).to(be_zero, failure_message)
      end
    end
    # rubocop:enable RSpec/MultipleExpectations
  end
end
