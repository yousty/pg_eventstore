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
              expect(subject.metadata).to eq(nil)
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
    end
  end
end
