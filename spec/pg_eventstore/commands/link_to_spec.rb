# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::LinkTo do
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
    let(:projection_stream) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyAwesomeProjection', stream_id: '123')
    end
    let(:events_stream) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyAwesomeStream', stream_id: '123')
    end

    describe 'linking persisted event' do
      subject { instance.call(projection_stream, event, options: options) }

      let(:event) do
        PgEventstore.client.append_to_stream(
          events_stream,
          PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :bar })
        )
      end
      let(:options) { {} }

      shared_examples 'linking the event' do
        it 'links the given event' do
          expect { subject }.to change { safe_read(projection_stream).count }.by(1)
        end
        it 'returns the link event' do
          aggregate_failures do
            is_expected.to eq([PgEventstore.client.read(projection_stream).last])
            expect(subject.first.stream_revision).to eq(stream_revision)
          end
        end

        describe 'link' do
          subject { super(); PgEventstore.client.read(projection_stream).last }

          it 'has correct attributes' do
            aggregate_failures do
              expect(subject.id).to be_a(String).and match(EventHelpers::UUID_REGEXP)
              expect(subject.global_position).to be_a(Integer)
              expect(subject.stream_revision).to eq(stream_revision)
              expect(subject.stream).to eq(projection_stream)
              expect(subject.type).to eq(PgEventstore::Event::LINK_TYPE)
              expect(subject.data).to eq({})
              expect(subject.metadata).to eq({})
              expect(subject.created_at).to be_between(Time.now - 1, Time.now + 1)
              expect(subject.link_id).to eq(event.id)
              expect(subject.link_partition_id).to(
                eq(partition_queries.event_type_partition(events_stream, event.type)['id'])
              )
            end
          end
        end
      end

      context 'when no options are given' do
        it_behaves_like 'linking the event' do
          let(:stream_revision) { 0 }
        end
      end

      context 'when :expected_revision option is :any' do
        let(:options) { { expected_revision: :any } }
        let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }

        before do
          PgEventstore.client.link_to(
            projection_stream, PgEventstore.client.append_to_stream(events_stream, another_event)
          )
        end

        it_behaves_like 'linking the event' do
          let(:stream_revision) { 1 }
        end
      end

      context 'when :expected_revision option is :no_stream' do
        let(:options) { { expected_revision: :no_stream } }

        context 'when stream exists' do
          let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }

          before do
            PgEventstore.client.link_to(
              projection_stream, PgEventstore.client.append_to_stream(events_stream, another_event)
            )
          end

          it 'raises error' do
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedRevisionError,
                "Expected stream #{projection_stream.to_hash.inspect} to be absent, but it actually exists."
              )
            )
          end
        end

        context 'when stream does not exist' do
          it_behaves_like 'linking the event' do
            let(:stream_revision) { 0 }
          end
        end
      end

      context 'when :expected_revision option is :stream_exists' do
        let(:options) { { expected_revision: :stream_exists } }

        context 'when stream exists' do
          let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }

          before do
            PgEventstore.client.link_to(
              projection_stream, PgEventstore.client.append_to_stream(events_stream, another_event)
            )
          end

          it_behaves_like 'linking the event' do
            let(:stream_revision) { 1 }
          end
        end

        context 'when stream does not exist' do
          it 'raises error' do
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedRevisionError,
                "Expected stream #{projection_stream.to_hash.inspect} to exist, but it doesn't."
              )
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
            PgEventstore.client.link_to(
              projection_stream, PgEventstore.client.append_to_stream(events_stream, another_event)
            )
          end

          it_behaves_like 'linking the event' do
            let(:stream_revision) { 1 }
          end
        end

        context "when expected revision does not match stream's revision" do
          let(:another_event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :baz }) }
          let(:expected_revision) { 1 }

          before do
            PgEventstore.client.link_to(
              projection_stream, PgEventstore.client.append_to_stream(events_stream, another_event)
            )
          end

          it 'raises error' do
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedRevisionError,
                "#{projection_stream.to_hash.inspect} stream revision #{expected_revision} is expected, but actual stream revision is 0."
              )
            )
          end
        end

        context "when stream does not exist" do
          it 'raises error' do
            expect { subject }.to(
              raise_error(
                PgEventstore::WrongExpectedRevisionError,
                "#{projection_stream.to_hash.inspect} stream revision #{expected_revision} is expected, but stream does not exist."
              )
            )
          end
        end
      end

      context 'when middleware is present' do
        let(:middlewares) { [DummyMiddleware.new] }

        it 'modifies the link using it' do
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
              def serialize(event)
                event.link_id = -1
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

      context 'when middleware which changes #type is given' do
        let(:middlewares) { [middleware] }
        let(:middleware) do
          Class.new do
            class << self
              def serialize(event)
                event.type = 'Baz'
              end
            end
          end
        end

        it_behaves_like 'read only attribute' do
          let(:attribute) { :type }
        end
      end

      context "when link's class is resolved" do
        let(:event_class) { Class.new(PgEventstore::Event) }
        let(:event_class_resolver) { proc { |_event_type| DummyClass } }

        before do
          stub_const('DummyClass', event_class)
        end

        it 'recognizes it' do
          expect(subject.first).to be_a(DummyClass)
        end
      end

      context 'when "all" stream is given as a stream to link events' do
        let(:projection_stream) { PgEventstore::Stream.all_stream }

        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::SystemStreamError,
              "Stream #{projection_stream.inspect} is a system stream and can't be used to append events."
            )
          )
        end
      end

      context 'when system stream is given as a stream to link events' do
        let(:projection_stream) { PgEventstore::Stream.new(context: '$et', stream_name: 'SomeEvent', stream_id: '') }

        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::SystemStreamError,
              "Stream #{projection_stream.inspect} is a system stream and can't be used to append events."
            )
          )
        end
      end
    end

    describe 'linking multiple events' do
      subject { instance.call(projection_stream, event1, event2, options: options) }

      let(:event1) do
        PgEventstore.client.append_to_stream(
          events_stream,
          PgEventstore::Event.new(type: 'MyAwesomeEvent1', data: { foo: :bar })
        )
      end
      let(:event2) do
        PgEventstore.client.append_to_stream(
          events_stream,
          PgEventstore::Event.new(type: 'MyAwesomeEvent2', data: { foo: :baz })
        )
      end
      let(:options) { {} }

      it 'links the given events' do
        expect { subject }.to change { safe_read(projection_stream).count }.by(2)
      end

      describe 'first link' do
        subject { super(); PgEventstore.client.read(projection_stream).first }

        it 'has correct attributes' do
          aggregate_failures do
            expect(subject.global_position).to be_a(Integer)
            expect(subject.stream_revision).to eq(0)
            expect(subject.stream).to eq(projection_stream)
            expect(subject.type).to eq(PgEventstore::Event::LINK_TYPE)
            expect(subject.data).to eq({})
            expect(subject.metadata).to eq({})
            expect(subject.created_at).to be_between(Time.now - 1, Time.now + 1)
            expect(subject.link_id).to eq(event1.id)
            expect(subject.link_partition_id).to(
              eq(partition_queries.event_type_partition(events_stream, event1.type)['id'])
            )
          end
        end
      end

      describe 'second link' do
        subject { super(); PgEventstore.client.read(projection_stream).last }

        it 'has correct attributes' do
          aggregate_failures do
            expect(subject.global_position).to be_a(Integer)
            expect(subject.stream_revision).to eq(1)
            expect(subject.stream).to eq(projection_stream)
            expect(subject.type).to eq(PgEventstore::Event::LINK_TYPE)
            expect(subject.data).to eq({})
            expect(subject.metadata).to eq({})
            expect(subject.created_at).to be_between(Time.now - 1, Time.now + 1)
            expect(subject.link_id).to eq(event2.id)
            expect(subject.link_partition_id).to(
              eq(partition_queries.event_type_partition(events_stream, event2.type)['id'])
            )
          end
        end
      end
    end

    describe 'linking non-existing event' do
      context 'when event#id is nil' do
        subject { instance.call(projection_stream, event) }

        let(:event) { PgEventstore::Event.new }

        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::NotPersistedEventError,
              "Event with #id #{nil.inspect} must be present, but it could not be found."
            )
          )
        end
      end

      context 'when event#id is present' do
        subject { instance.call(projection_stream, event) }

        let(:event) { PgEventstore::Event.new(id: SecureRandom.uuid) }

        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::NotPersistedEventError,
              "Event with #id #{event.id.inspect} must be present, but it could not be found."
            )
          )
        end
      end
    end
  end
end
