# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::Append do
  let(:instance) { described_class.new(PgEventstore.connection, middlewares, event_class_resolver) }
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#call' do
    let(:stream) { PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyAwesomeStream', stream_id: '123') }

    describe 'appending single event' do
      subject { instance.call(stream, event, options: options) }

      let(:event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :bar }) }
      let(:options) { {} }

      shared_examples 'appending the event' do
        it 'appends the given event' do
          expect { subject }.to change { safe_read(stream).count }.by(1)
        end

        describe 'appended event' do
          subject { super(); PgEventstore.client.read(stream).last }

          it 'has correct attributes' do
            aggregate_failures do
              expect(subject.global_position).to be_a(Integer)
              expect(subject.stream_revision).to eq(stream_revision)
              expect(subject.stream).to eq(stream)
              expect(subject.type).to eq('MyAwesomeEvent')
              expect(subject.data).to eq('foo' => 'bar')
              expect(subject.metadata).to eq({})
              expect(subject.created_at).to be_between(Time.now - 1, Time.now + 1)
              expect(subject.link_id).to eq(nil)
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
                PgEventstore::WrongExpectedVersionError,
                "Expected stream to be absent, but it actually exists."
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
              raise_error(PgEventstore::WrongExpectedVersionError, "Expected stream to exist, but it doesn't.")
            )
          end
        end
      end

      context 'when :expected_revision is a number' do
        let(:options) { { expected_revision: expected_revision } }
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
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedVersionError,
                "Stream revision #{expected_revision} is expected, but actual stream revision is 0."
              )
            )
          end
        end

        context "when stream does not exist" do
          it 'raises error' do
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedVersionError,
                "Stream revision #{expected_revision} is expected, but stream does not exist."
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
    end

    describe 'appending multiple events' do
      subject { instance.call(stream, event1, event2, options: options) }

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

    it 'checks it' do
      5.times.flat_map do |i|
        t1 = Thread.new do
          sleep 0.1 + i / 10.0
          instance.call(stream, *([event1] * events_count_mapping['some-event']))
        end
        t2 = Thread.new do
          sleep 0.1 + i / 10.0
          instance.call(stream, *([event2] * events_count_mapping['some-event2']))
        end
        t3 = Thread.new do
          sleep 0.1 + i / 10.0
          instance.call(stream, *([event3] * events_count_mapping['some-event3']))
        end
        [t1, t2, t3]
      end.each(&:join)
      events = PgEventstore.client.read(stream)
      sequences = events.map(&:type).each_with_object([]) do |type, arr|
        arr.last&.last == type ? arr.last.push(type) : arr.push([type])
      end

      expect(events.map(&:stream_revision)).to eq((0..(events.size - 1)).to_a)

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
  end
end