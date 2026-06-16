# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::DeleteEvent do
  let(:instance) { described_class.new(queries) }
  let(:queries) { PgEventstore::Queries.new(maintenance: maintenance_queries, events_global_index: events_idx_queries) }
  let(:maintenance_queries) { PgEventstore::MaintenanceQueries.new(PgEventstore.connection) }
  let(:events_idx_queries) { PgEventstore::EventsGlobalIndexQueries.new(PgEventstore.connection, query_strategy) }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

  describe '#call' do
    subject { instance.call(event, force:) }

    let(:event) { PgEventstore::Event.new }
    let(:force) { false }
    let(:streams_global_idx_queries) do
      PgEventstore::StreamsGlobalIndexQueries.new(
        PgEventstore.connection,
        query_strategy
      )
    end
    let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

    context 'when non-persisted event is provided' do
      it 'raises error' do
        expect { subject }.to raise_error(ArgumentError, a_string_including('Event#stream is nil'))
      end
    end

    context 'when non-existing event is provided' do
      let(:event) { PgEventstore::Event.new(stream:) }
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      it { is_expected.to eq(false) }
    end

    context 'when event exists' do
      let(:event) do
        event = PgEventstore::Event.new(data: { foo: :bar })
        PgEventstore.client.append_to_stream(stream, event)
      end
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      context 'when there is only one event in the stream' do
        let(:another_event) do
          event = PgEventstore::Event.new(data: { foo: :bar })
          PgEventstore.client.append_to_stream(another_stream, event)
        end
        let(:another_stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2') }

        before do
          event
          another_event
        end

        it 'deletes StreamsGlobalIndex' do
          expect { subject }.to change { streams_global_idx_queries.find_by(stream) }.to(nil)
        end
        it 'deletes events global index of the given stream' do
          expect { subject }.to change {
            query_strategy.exec_params(
              'select global_position from events_global_index where global_position = $1',
              [event.global_position]
            ).to_a.first&.[]('global_position')
          }.to(nil)
        end
        it 'does not delete events of another stream' do
          expect { subject }.not_to change { safe_read(another_stream) }
        end
        it 'does not delete events global index of another stream' do
          expect { subject }.not_to change {
            query_strategy.exec_params(
              'select global_position from events_global_index where global_position = $1',
              [another_event.global_position]
            ).map { _1['global_position'] }
          }.from([another_event.global_position])
        end
        it 'does not delete StreamGlobalIndex of another stream' do
          expect { subject }.not_to change { streams_global_idx_queries.find_by(another_stream) }
        end
        it 'deletes the given event' do
          expect { subject }.to change { safe_read(stream) }.to([])
        end
        it { is_expected.to eq(true) }
      end

      context 'when there are multiple events in the stream' do
        shared_examples 'event gets deleted' do
          let!(:another_event) do
            event = PgEventstore::Event.new(data: { foo: :bar })
            PgEventstore.client.append_to_stream(another_stream, event)
          end
          let(:another_stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2') }

          before do
            query_strategy.exec_params(
              'insert into event_subscription_positions ("global_position") values ($1)', [event.global_position]
            )
          end

          it 'deletes the given event' do
            expect { subject }.to change { safe_read(stream).map(&:id) }.to(rest_events.map(&:id))
          end
          it 'deletes the record from "events" table' do
            expect { subject }.to change {
              query_strategy.exec_params(
                'select global_position from events where global_position = $1',
                [event.global_position]
              ).to_a.first&.[]('global_position')
            }.to(nil)
          end
          it 'deletes the record from "event_subscription_positions_unprocessed" table' do
            expect { subject }.to change {
              query_strategy.exec_params(
                'select global_position from event_subscription_positions_unprocessed where global_position = $1',
                [event.global_position]
              ).to_a.first&.[]('global_position')
            }.to(nil)
          end
          it 'deletes the record from "event_subscription_positions" table' do
            expect { subject }.to change {
              query_strategy.exec_params(
                'select global_position from event_subscription_positions where global_position = $1',
                [event.global_position]
              ).to_a.first&.[]('global_position')
            }.to(nil)
          end
          it 'adjusts stream revisions of the rest of events' do
            expect { subject }.to change { safe_read(stream).map(&:stream_revision) }.to((0...rest_events.size).to_a)
          end
          it 'adjusts stream revisions of events global index' do
            stream_idx = streams_global_idx_queries.find_by!(stream)
            expect { subject }.to change {
              query_strategy.exec_params(
                'select stream_revision from events_global_index where streams_global_index_id = $1',
                [stream_idx.id]
              ).sort_by { _1['stream_revision'] }.map { _1['stream_revision'] }
            }.to((0...rest_events.size).to_a)
          end
          it 'adjusts stream revision of StreamGlobalIndex' do
            expect { subject }.to change {
              streams_global_idx_queries.find_by!(stream).stream_revision
            }.to(rest_events.size - 1)
          end
          it { is_expected.to eq(true) }
          it 'does not update events of another stream' do
            expect { subject }.not_to change { safe_read(another_stream) }
          end
          it 'does not update StreamGlobalIndex of another stream' do
            expect { subject }.not_to change { streams_global_idx_queries.find_by!(another_stream).stream_revision }
          end
          it 'does not update stream revisions of events global index of another stream' do
            stream_idx = streams_global_idx_queries.find_by!(another_stream)
            expect { subject }.not_to change {
              query_strategy.exec_params(
                'select stream_revision from events_global_index where streams_global_index_id = $1',
                [stream_idx.id]
              ).sort_by { _1['stream_revision'] }.map { _1['stream_revision'] }
            }
          end
        end

        context 'when deleting 0-revision event' do
          let(:another_events) { PgEventstore.client.append_to_stream(stream, 3.times.map { PgEventstore::Event.new }) }

          before do
            event
            another_events
          end

          it 'adjusts StreamGlobalIndex#starting_position' do
            expect { subject }.to change {
              streams_global_idx_queries.find_by!(stream).starting_position
            }.to(another_events.first.global_position)
          end
        end

        context 'when there are less than MAX_RECORDS_TO_LOCK events after the given event in the stream' do
          let(:another_events) { PgEventstore.client.append_to_stream(stream, 3.times.map { PgEventstore::Event.new }) }

          before do
            event
            another_events
          end

          it_behaves_like 'event gets deleted' do
            let(:rest_events) { another_events }
          end
        end

        context 'when there are more than MAX_RECORDS_TO_LOCK events after the given event in the stream' do
          let(:another_events) { PgEventstore.client.append_to_stream(stream, 2.times.map { PgEventstore::Event.new }) }

          before do
            stub_const("#{described_class}::MAX_RECORDS_TO_LOCK", 0)
            event
            another_events
          end

          it 'raises error' do
            expect { subject }.to raise_error(PgEventstore::TooManyRecordsToLockError, /Too many records/)
          end
          it 'does not delete any events' do
            expect {
              begin
                subject
              rescue PgEventstore::TooManyRecordsToLockError
              end
            }.not_to change { safe_read(stream) }.from([event, *another_events])
          end
          it 'keeps correct stream revisions sequence' do
            expect {
              begin
                subject
              rescue PgEventstore::TooManyRecordsToLockError
              end
            }.not_to change { safe_read(stream).map(&:stream_revision) }.from((0..2).to_a)
          end

          context 'when "force" flag is set to true' do
            let(:force) { true }

            it_behaves_like 'event gets deleted' do
              let(:rest_events) { another_events }
            end
          end
        end

        context 'when the given event is in the middle of the stream' do
          let(:another_events1) { PgEventstore.client.append_to_stream(stream, 2.times.map { PgEventstore::Event.new }) }
          let(:another_events2) { PgEventstore.client.append_to_stream(stream, 3.times.map { PgEventstore::Event.new }) }

          before do
            another_events1
            event
            another_events2
          end

          it_behaves_like 'event gets deleted' do
            let(:rest_events) { [*another_events1, *another_events2] }
          end
        end

        context 'when the given event is in the end of the stream' do
          let(:another_events) { PgEventstore.client.append_to_stream(stream, 3.times.map { PgEventstore::Event.new }) }

          before do
            another_events
            event
          end

          it_behaves_like 'event gets deleted' do
            let(:rest_events) { another_events }
          end
        end
      end
    end

    describe 'event deletion consistency' do
      let(:another_events) { PgEventstore.client.append_to_stream(stream, 3.times.map { PgEventstore::Event.new }) }
      let(:event) do
        event = PgEventstore::Event.new(data: { foo: :bar })
        PgEventstore.client.append_to_stream(stream, event)
      end
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:concurrent_deletion) { Thread.new { instance.call(event, force:) } }
      let(:transaction_queries) { PgEventstore::TransactionQueries.new(PgEventstore.connection) }

      before do
        event
        another_events
        # Slow down a transaction commit a bit to simulate concurrent deletion of the same event
        allow(transaction_queries).to receive(:transaction).and_wrap_original do |orig_meth, *args, **kwargs, &orig_blk|
          blk = proc do
            orig_blk.call.tap do
              sleep 0.5
            end
          end
          orig_meth.call(*args, **kwargs, &blk)
        end
        allow(maintenance_queries).to receive(:transaction_queries).and_return(transaction_queries)
        concurrent_deletion
      end

      after do
        concurrent_deletion.exit
      end

      it 'deletes the given event' do
        expect { subject }.to change {
          safe_read(stream).map(&:id)
        }.from([event, *another_events].map(&:id)).to(another_events.map(&:id))
      end
      it 'adjusts stream revisions of the rest of events' do
        expect { subject }.to change { safe_read(stream).map(&:stream_revision) }.from((0..3).to_a).to((0..2).to_a)
      end
    end
  end
end
