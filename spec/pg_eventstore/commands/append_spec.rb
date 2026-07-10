# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::Append do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(
      events: event_queries,
      partitions: partition_queries,
      transactions: transaction_queries,
      events_global_index: events_global_index_queries,
      streams_global_index: streams_global_index_queries,
      event_subscription_positions: event_subscription_position_queries,
      index_filtering: index_filtering_queries,
      event_markers: event_marker_queries
    )
  end
  let(:transaction_queries) { PgEventstore::TransactionQueries.new(PgEventstore.connection) }
  let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }
  let(:events_global_index_queries) do
    PgEventstore::EventsGlobalIndexQueries.new(PgEventstore.connection, query_strategy)
  end
  let(:streams_global_index_queries) do
    PgEventstore::StreamsGlobalIndexQueries.new(PgEventstore.connection, query_strategy)
  end
  let(:event_queries) { PgEventstore::EventQueries.new(PgEventstore.connection) }
  let(:event_subscription_position_queries) do
    PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection)
  end
  let(:index_filtering_queries) do
    PgEventstore::IndexFilteringQueries.new(PgEventstore.connection, query_strategy)
  end
  let(:event_marker_queries) do
    PgEventstore::EventMarkerQueries.new(PgEventstore.connection, query_strategy)
  end
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }
  let(:deserializer) { PgEventstore::EventDeserializer.new(middlewares, event_class_resolver) }
  let(:event_modifier) do
    PgEventstore::Commands::EventModifiers::PrepareRegularEvent.new(PgEventstore::EventSerializer.new(middlewares))
  end
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#call' do
    let(:stream) { PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyAwesomeStream', stream_id: '123') }

    describe 'appending single event' do
      subject { instance.call(stream, event, event_modifier:, deserializer:, options:) }

      let(:event) { PgEventstore::Event.new(type: 'MyAwesomeEvent', data: { foo: :bar }) }
      let(:options) { {} }

      shared_examples 'appending the event' do
        it 'appends the given event' do
          expect { subject }.to change { safe_read(stream).count }.by(1)
        end
        it 'returns the appended event' do
          is_expected.to eq([PgEventstore.client.read(stream).last])
        end
        it 'creates unprocessed subscription position' do
          builder = PgEventstore::SQLBuilder.new.from('event_subscription_positions_unprocessed')
          builder.select('count(*) as c_all')
          expect { subject }.to change { query_strategy.exec_params(*builder.to_exec_params).first['c_all'] || 0 }.by(1)
        end

        describe 'appended event' do
          subject { super(); PgEventstore.client.read(stream).last }

          before do
            # Assign attributes that should be re-assigned during the append process. This way we ensure user-defined
            # value does not propagate into the database
            event.link_global_position = -1
            event.link_partition_id = -1
            event.stream_revision = -1
          end

          it 'has correct attributes' do
            aggregate_failures do
              expect(subject.id).to be_a(String)
              expect(subject.global_position).to be_a(Integer)
              expect(subject.stream_revision).to eq(stream_revision)
              expect(subject.stream).to eq(stream)
              expect(subject.type).to eq('MyAwesomeEvent')
              expect(subject.data).to eq('foo' => 'bar')
              expect(subject.metadata).to eq({})
              expect(subject.created_at).to be_between(Time.now - 1, Time.now + 1)
              expect(subject.link_global_position).to eq(nil)
              expect(subject.link_partition_id).to eq(nil)
              expect(subject.markers).to eq([])
            end
          end
        end

        describe 'created unprocessed position' do
          let(:created_event) { PgEventstore.client.read(stream).last }
          let(:position) do
            builder = PgEventstore::SQLBuilder.new.from('event_subscription_positions_unprocessed')
            builder.order('global_position desc').limit(1)
            query_strategy.exec_params(*builder.to_exec_params).first
          end

          before do
            subject
          end

          it 'has correct attributes' do
            expect(position).to eq('global_position' => created_event.global_position)
          end
        end

        describe 'markers' do
          let(:created_event) { PgEventstore.client.read(stream).last }

          before do
            event.markers = %w[foo bar]
            event.feature_markers = [PgEventstore::FeatureMarker.new(marker: 'baz')]
            subject
          end

          it 'persists markers' do
            filtered_by_feature_marker = PgEventstore.client.read(
              PgEventstore::Stream.all_stream, options: { filter: { event_types: [{ markers: ['baz'] }] } }
            ).last
            aggregate_failures do
              expect(created_event.markers).to eq(%w[foo bar])
              expect(created_event.feature_markers.map(&:marker)).to eq([])
              expect(filtered_by_feature_marker).to eq(created_event)
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

      context 'when :expected_revision is a event_type-to-revision map' do
        context 'when expected revision is :any' do
          let(:options) { { expected_revision: { event.type => :any } } }

          context 'when another event with same type exists' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

            before do
              PgEventstore.client.append_to_stream(stream, another_event)
            end

            it_behaves_like 'appending the event' do
              let(:stream_revision) { 1 }
            end
          end

          context 'when event with same type exists in another stream' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }
            let(:another_stream) { PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1') }

            before do
              PgEventstore.client.append_to_stream(another_stream, another_event)
            end

            it_behaves_like 'appending the event' do
              let(:stream_revision) { 0 }
            end
          end
        end

        context 'when expected revision is a number' do
          let(:options) { { expected_revision: { event.type => 0 } } }

          context 'when event with same type exists with the expected revision' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

            before do
              PgEventstore.client.append_to_stream(stream, another_event)
            end

            it_behaves_like 'appending the event' do
              let(:stream_revision) { 1 }
            end
          end

          context 'when event with same type exists with another revision' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

            before do
              PgEventstore.client.append_to_stream(stream, another_event)
              PgEventstore.client.append_to_stream(stream, another_event)
            end

            it 'raises error' do
              expect { subject }.to(
                raise_error(
                  PgEventstore::WrongExpectedTypesRevisionError,
                  <<~TEXT.strip
                    Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with 0 \
                    revision, but it actually has 1 revision.
                  TEXT
                )
              )
            end
          end

          context 'when event with another type exists with expected revision' do
            let(:another_event) { PgEventstore::Event.new(type: 'Bar', data: { foo: :baz }) }

            before do
              PgEventstore.client.append_to_stream(stream, another_event)
            end

            it 'raises error' do
              expect { subject }.to(
                raise_error(
                  PgEventstore::WrongExpectedTypesRevisionError,
                  <<~TEXT.strip
                    Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with 0 revision, \
                    but this event does not exist.
                  TEXT
                )
              )
            end
          end

          context 'when event with same type exists in another stream' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }
            let(:another_stream) { PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1') }

            before do
              PgEventstore.client.append_to_stream(another_stream, another_event)
            end

            it 'raises error' do
              expect { subject }.to(
                raise_error(
                  PgEventstore::WrongExpectedTypesRevisionError,
                  <<~TEXT.strip
                    Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with 0 revision, but \
                    this event does not exist.
                  TEXT
                )
              )
            end
          end
        end

        context 'when expected revision is :event_exists' do
          let(:options) { { expected_revision: { event.type => :event_exists } } }

          context 'when event with same type exists' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

            before do
              PgEventstore.client.append_to_stream(stream, another_event)
            end

            it_behaves_like 'appending the event' do
              let(:stream_revision) { 1 }
            end
          end

          context 'when event with same type exists with any revision' do
            let(:another_event1) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }
            let(:another_event2) { PgEventstore::Event.new(type: 'Bar', data: { foo: :baz }) }

            before do
              PgEventstore.client.append_to_stream(stream, another_event2)
              PgEventstore.client.append_to_stream(stream, another_event1)
            end

            it_behaves_like 'appending the event' do
              let(:stream_revision) { 2 }
            end
          end

          context 'when event with same type exists in another stream' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }
            let(:another_stream) { PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1') }

            before do
              PgEventstore.client.append_to_stream(another_stream, another_event)
            end

            it 'raises error' do
              expect { subject }.to(
                raise_error(
                  PgEventstore::WrongExpectedTypesRevisionError,
                  <<~TEXT.strip
                    Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some revision, but \
                    this event does not exist.
                  TEXT
                )
              )
            end
          end
        end

        context 'when expected revision is :no_event' do
          let(:options) { { expected_revision: { event.type => :no_event } } }

          context 'when event with same type exists' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

            before do
              PgEventstore.client.append_to_stream(stream, another_event)
            end

            it 'raises error' do
              expect { subject }.to(
                raise_error(
                  PgEventstore::WrongExpectedTypesRevisionError,
                  <<~TEXT.strip
                    Expected #{stream.to_hash.inspect} stream not to contain "#{event.type}" event, but it actually \
                    exists.
                  TEXT
                )
              )
            end
          end

          context 'when event with another type exists' do
            let(:another_event) { PgEventstore::Event.new(type: 'Bar', data: { foo: :baz }) }

            before do
              PgEventstore.client.append_to_stream(stream, another_event)
            end

            it_behaves_like 'appending the event' do
              let(:stream_revision) { 1 }
            end
          end

          context 'when event with same type exists in another stream' do
            let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }
            let(:another_stream) { PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1') }

            before do
              PgEventstore.client.append_to_stream(another_stream, another_event)
            end

            it_behaves_like 'appending the event' do
              let(:stream_revision) { 0 }
            end
          end
        end
      end

      describe 'markers based expected revision' do
        describe 'validating markers of specific type' do
          context 'when expected revision is :any' do
            let(:options) do
              { expected_revision: { event.type => { expected_revision: :any, markers: %w[foo bar] } } }
            end

            context 'when another event with same type exists' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz })
              end

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when another event with same type and markers exists' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when another event with same type and markers exists in another stream' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end
              let(:another_stream) do
                PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1')
              end

              before do
                PgEventstore.client.append_to_stream(another_stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 0 }
              end
            end
          end

          context 'when expected revision is :event_exists' do
            let(:options) do
              { expected_revision: { event.type => { expected_revision: :event_exists, markers: %w[foo bar] } } }
            end

            context 'when event with same type exists' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some of "foo", \
                      "bar" marker(s) with some revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end

            context 'when event with same type and one of the given markers exists' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when event with same type and any other marker exists' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['baz']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some of "foo", \
                      "bar" marker(s) with some revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end

            context 'when multiple events with same type, matching markers exist' do
              let(:another_event1) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['bar']) }
              let(:another_event2) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event1)
                PgEventstore.client.append_to_stream(stream, another_event2)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 2 }
              end
            end

            context 'when another event with same type and markers exists in another stream' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end
              let(:another_stream) do
                PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1')
              end

              before do
                PgEventstore.client.append_to_stream(another_stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some of "foo", \
                      "bar" marker(s) with some revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end
          end

          context 'when expected revision is :no_event' do
            let(:options) do
              { expected_revision: { event.type => { expected_revision: :no_event, markers: %w[foo bar] } } }
            end

            context 'when event with same type exists' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when event with same type and one of the given markers exists' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream not to contain "#{event.type}" event with some of \
                      "foo", "bar" marker(s), but it actually exists.
                    TEXT
                  )
                )
              end
            end

            context 'when event with same type and another marker exists' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['baz']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when multiple events with same type, matching different markers exist' do
              let(:another_event1) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['bar']) }
              let(:another_event2) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event1)
                PgEventstore.client.append_to_stream(stream, another_event2)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream not to contain "#{event.type}" event with some of \
                      "foo", "bar" marker(s), but it actually exists.
                    TEXT
                  )
                )
              end
            end

            context 'when another event with same type and markers exists in another stream' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end
              let(:another_stream) do
                PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1')
              end

              before do
                PgEventstore.client.append_to_stream(another_stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 0 }
              end
            end
          end

          context 'when expected revision is a number' do
            let(:options) do
              { expected_revision: { event.type => { expected_revision: 0, markers: ['foo', 'bar'] } } }
            end

            context 'when event with same type exists with the expected revision' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some of "foo", \
                      "bar" marker(s) with 0 revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end

            context 'when event with same type and one of the given markers exists with the expected revision' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when event with same type and any other marker exists with the expected revision' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['baz']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some of "foo", \
                      "bar" marker(s) with 0 revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end

            context 'when event with same type and any marker exists with different revision' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some of "foo", \
                      "bar" marker(s) with 0 revision, but it actually has 1 revision.
                    TEXT
                  )
                )
              end
            end

            context 'when multiple events with same type, matching markers exists with various revisions' do
              let(:another_event1) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['bar']) }
              let(:another_event2) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event1)
                PgEventstore.client.append_to_stream(stream, another_event2)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some of "foo", \
                      "bar" marker(s) with 0 revision, but it actually has 1 revision.
                    TEXT
                  )
                )
              end
            end

            context 'when another event with same type and markers exists in another stream' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end
              let(:another_stream) do
                PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1')
              end

              before do
                PgEventstore.client.append_to_stream(another_stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain "#{event.type}" event with some of "foo", \
                      "bar" marker(s) with 0 revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end
          end
        end

        describe 'validating markers of :any type' do
          context 'when expected revision is :any' do
            let(:options) do
              { expected_revision: { any: { expected_revision: :any, markers: %w[foo bar] } } }
            end

            context 'when another event with same type exists' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz })
              end

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when another event with same type and markers exists' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when another event with same type and markers exists in another stream' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end
              let(:another_stream) do
                PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1')
              end

              before do
                PgEventstore.client.append_to_stream(another_stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 0 }
              end
            end
          end

          context 'when expected revision is :event_exists' do
            let(:options) do
              { expected_revision: { any: { expected_revision: :event_exists, markers: %w[foo bar] } } }
            end

            context 'when some event exists' do
              let(:another_event) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain any event with some of "foo", \
                      "bar" marker(s) with some revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end

            context 'when some event with one of the given markers exists' do
              let(:another_event) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when some event with another marker exists' do
              let(:another_event) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['baz']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain any event with some of "foo", \
                      "bar" marker(s) with some revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end

            context 'when multiple events with matching markers exist' do
              let(:another_event1) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['bar']) }
              let(:another_event2) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event1)
                PgEventstore.client.append_to_stream(stream, another_event2)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 2 }
              end
            end

            context 'when some event with same markers exists in another stream' do
              let(:another_event) do
                PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: event.markers)
              end
              let(:another_stream) do
                PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1')
              end

              before do
                PgEventstore.client.append_to_stream(another_stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain any event with some of "foo", \
                      "bar" marker(s) with some revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end
          end

          context 'when expected revision is :no_event' do
            let(:options) do
              { expected_revision: { any: { expected_revision: :no_event, markers: %w[foo bar] } } }
            end

            context 'when some event exists' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when some event with one of the given markers exists' do
              let(:another_event) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream not to contain any event with some of \
                      "foo", "bar" marker(s), but it actually exists.
                    TEXT
                  )
                )
              end
            end

            context 'when some event with another marker exists' do
              let(:another_event) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['baz']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when multiple events with matching different markers exist' do
              let(:another_event1) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['bar']) }
              let(:another_event2) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event1)
                PgEventstore.client.append_to_stream(stream, another_event2)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream not to contain any event with some of \
                      "foo", "bar" marker(s), but it actually exists.
                    TEXT
                  )
                )
              end
            end

            context 'when another event with same markers exists in another stream' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end
              let(:another_stream) do
                PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1')
              end

              before do
                PgEventstore.client.append_to_stream(another_stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 0 }
              end
            end
          end

          context 'when expected revision is a number' do
            let(:options) do
              { expected_revision: { any: { expected_revision: 0, markers: %w[foo bar] } } }
            end

            context 'when some event exists with the expected revision' do
              let(:another_event) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain any event with some of "foo", \
                      "bar" marker(s) with 0 revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end

            context 'when some event with one of the given markers exists with the expected revision' do
              let(:another_event) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it_behaves_like 'appending the event' do
                let(:stream_revision) { 1 }
              end
            end

            context 'when some event with another marker exists with the expected revision' do
              let(:another_event) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['baz']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain any event with some of "foo", \
                      "bar" marker(s) with 0 revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end

            context 'when some event with any given marker exists with different revision' do
              let(:another_event) { PgEventstore::Event.new(type: 'Baz', data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event)
                PgEventstore.client.append_to_stream(stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain any event with some of "foo", \
                      "bar" marker(s) with 0 revision, but it actually has 1 revision.
                    TEXT
                  )
                )
              end
            end

            context 'when multiple events with matching markers exists with various revisions' do
              let(:another_event1) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['bar']) }
              let(:another_event2) { PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: ['foo']) }

              before do
                PgEventstore.client.append_to_stream(stream, another_event1)
                PgEventstore.client.append_to_stream(stream, another_event2)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain any event with some of "foo", \
                      "bar" marker(s) with 0 revision, but it actually has 1 revision.
                    TEXT
                  )
                )
              end
            end

            context 'when another event with the given markers exists in another stream' do
              let(:another_event) do
                PgEventstore::Event.new(type: event.type, data: { foo: :baz }, markers: event.markers)
              end
              let(:another_stream) do
                PgEventstore::Stream.new(context: 'AnotherCtx', stream_name: 'Foo', stream_id: '1')
              end

              before do
                PgEventstore.client.append_to_stream(another_stream, another_event)
              end

              it 'raises error' do
                expect { subject }.to(
                  raise_error(
                    PgEventstore::WrongExpectedTypesRevisionError,
                    <<~TEXT.strip
                      Expected #{stream.to_hash.inspect} stream to contain any event with some of "foo", \
                      "bar" marker(s) with 0 revision, but this event does not exist.
                    TEXT
                  )
                )
              end
            end
          end
        end
      end

      context 'when middleware is present' do
        let(:middlewares) { [DummyMiddleware.new] }

        it 'deserializes event after it was persisted' do
          expect(subject.first.metadata).to eq('dummy_secret' => DummyMiddleware::DECR_SECRET)
        end
        it 'serializes event correctly' do
          from_db_without_middleware = PgEventstore.client.read(
            PgEventstore::Stream.all_stream, options: { from_position: subject.first.global_position }
          ).first
          expect(from_db_without_middleware.metadata).to eq('dummy_secret' => DummyMiddleware::ENCR_SECRET)
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

      context 'when middleware which changes #link_global_position is given' do
        let(:middlewares) { [middleware] }
        let(:middleware) do
          Class.new do
            class << self
              include PgEventstore::Middleware

              def serialize(event)
                event.link_global_position = 0
              end
            end
          end
        end

        it_behaves_like 'read only attribute' do
          let(:attribute) { :link_global_position }
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
    end

    describe 'appending multiple events' do
      subject { instance.call(stream, event1, event2, event_modifier:, deserializer:, options:) }

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
            expect(subject.link_global_position).to eq(nil)
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
            expect(subject.link_global_position).to eq(nil)
            expect(subject.link_partition_id).to eq(nil)
          end
        end
      end
    end

    context 'when no events are provided' do
      subject { instance.call(stream, *[], event_modifier:, deserializer:, options: {}) }

      it 'raises error' do
        expect { subject }.to raise_error(ArgumentError, 'No events to append.')
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
          instance.call(stream, *([event1] * events_count_mapping['some-event']), event_modifier:, deserializer:)
        end
        t2 = Thread.new do
          sleep 0.1 + (i / 10.0)
          instance.call(stream, *([event2] * events_count_mapping['some-event2']), event_modifier:, deserializer:)
        end
        t3 = Thread.new do
          sleep 0.1 + (i / 10.0)
          instance.call(stream, *([event3] * events_count_mapping['some-event3']), event_modifier:, deserializer:)
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

  describe 'mix of expected revisions' do
    subject { instance.call(stream, *events_to_append, event_modifier:, deserializer:, options:) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyAwesomeStream', stream_id: '123') }
    let(:options) { {} }
    let(:events_to_append) { [] }

    describe 'case 1' do
      let(:options) { { expected_revision: { event1.type => 0, event2.type => :no_event } } }

      let(:events_to_append) { [event1, event2] }
      let(:event1) { PgEventstore::Event.new(type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(type: 'Bar') }

      before do
        PgEventstore.client.append_to_stream(stream, event1)
      end

      it 'publishes events' do
        expect { subject }.to change { safe_read(stream).count }.by(2)
      end
    end

    describe 'case 2' do
      let(:options) { { expected_revision: { event1.type => 0, event2.type => :event_exists } } }

      let(:events_to_append) { [event1, event2] }
      let(:event1) { PgEventstore::Event.new(type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(type: 'Bar') }

      before do
        PgEventstore.client.append_to_stream(stream, event1)
      end

      it 'raises error' do
        expect { subject }.to(
          raise_error(
            PgEventstore::WrongExpectedTypesRevisionError,
            <<~TEXT.strip
              Expected #{stream.to_hash.inspect} stream to contain "#{event2.type}" event with some revision, but \
              this event does not exist.
            TEXT
          )
        )
      end
    end

    describe 'case 3' do
      let(:options) do
        {
          expected_revision: {
            event1.type => { expected_revision: 0, markers: ['foo'] },
            event2.type => { expected_revision: 1, markers: ['bar'] },
          },
        }
      end

      let(:events_to_append) { [event1, event2] }
      let(:event1) { PgEventstore::Event.new(type: 'Foo', markers: %w[baz foo]) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', markers: %w[baz bar]) }

      before do
        PgEventstore.client.append_to_stream(stream, event1)
        PgEventstore.client.append_to_stream(stream, event2)
      end

      it 'publishes events' do
        expect { subject }.to change { safe_read(stream).count }.by(2)
      end
    end

    describe 'case 4' do
      let(:options) do
        {
          expected_revision: {
            event1.type => { expected_revision: 0, markers: ['foo'] },
            event2.type => { expected_revision: :no_event, markers: ['bar'] },
          },
        }
      end

      let(:events_to_append) { [event1, event2] }
      let(:event1) { PgEventstore::Event.new(type: 'Foo', markers: %w[baz foo]) }
      let(:event2) { PgEventstore::Event.new(type: 'Foo', markers: %w[baz bar]) }

      before do
        PgEventstore.client.append_to_stream(stream, event1)
        PgEventstore.client.append_to_stream(stream, event2)
      end

      it 'raises error' do
        expect { subject }.to(
          raise_error(
            PgEventstore::WrongExpectedTypesRevisionError,
            <<~TEXT.strip
              Expected #{stream.to_hash.inspect} stream not to contain "#{event2.type}" event with some of \
              "bar" marker(s), but it actually exists.
            TEXT
          )
        )
      end
    end

    describe 'case 5' do
      let(:options) do
        {
          expected_revision: {
            event1.type => 0,
            event2.type => { expected_revision: 1, markers: ['bar'] },
          },
        }
      end

      let(:events_to_append) { [event1, event2] }
      let(:event1) { PgEventstore::Event.new(type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', markers: %w[baz bar]) }

      before do
        PgEventstore.client.append_to_stream(stream, event1)
        PgEventstore.client.append_to_stream(stream, event2)
      end

      it 'publishes events' do
        expect { subject }.to change { safe_read(stream).count }.by(2)
      end
    end

    describe 'case 6' do
      let(:options) do
        {
          expected_revision: {
            event1.type => 0,
            event2.type => { expected_revision: :no_event, markers: ['bar'] },
          },
        }
      end

      let(:events_to_append) { [event1, event2] }
      let(:event1) { PgEventstore::Event.new(type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', markers: %w[baz bar]) }

      before do
        PgEventstore.client.append_to_stream(stream, event1)
        PgEventstore.client.append_to_stream(stream, event2)
      end

      it 'raises error' do
        expect { subject }.to(
          raise_error(
            PgEventstore::WrongExpectedTypesRevisionError,
            <<~TEXT.strip
              Expected #{stream.to_hash.inspect} stream not to contain "#{event2.type}" event with some of \
              "bar" marker(s), but it actually exists.
            TEXT
          )
        )
      end
    end

    describe 'multiple error messages' do
      let(:options) do
        {
          expected_revision: {
            event1.type => :event_exists,
            event2.type => { expected_revision: :event_exists, markers: ['bar'] },
          },
        }
      end

      let(:events_to_append) { [event1, event2] }
      let(:event1) { PgEventstore::Event.new(type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', markers: %w[baz bar]) }

      it 'raises error' do
        message1 = <<~TEXT.strip
          Expected #{stream.to_hash.inspect} stream to contain "#{event1.type}" event with some revision, but this \
          event does not exist.
        TEXT
        message2 = <<~TEXT.strip
          Expected #{stream.to_hash.inspect} stream to contain "#{event2.type}" event with some of \
          "bar" marker(s) with some revision, but this event does not exist.
        TEXT

        expect { subject }.to(
          raise_error(
            PgEventstore::WrongExpectedTypesRevisionError, [message1, message2].join('; ')
          )
        )
      end
    end
  end
end
