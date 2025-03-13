# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::DeleteEvent do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(maintenance: maintenance_queries, transactions: transaction_queries)
  end
  let(:transaction_queries) { PgEventstore::TransactionQueries.new(PgEventstore.connection) }
  let(:maintenance_queries) { PgEventstore::MaintenanceQueries.new(PgEventstore.connection) }

  describe '#call' do
    subject { instance.call(event, force: force) }

    let(:event) { PgEventstore::Event.new }
    let(:force) { false }

    context 'when event does not exist' do
      it { is_expected.to eq(false) }
    end

    context 'when event exists' do
      let(:event) do
        event = PgEventstore::Event.new(data: { foo: :bar })
        PgEventstore.client.append_to_stream(stream, event)
      end
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      shared_examples 'event gets deleted' do
        it 'deletes the given event' do
          expect { subject }.to change { safe_read(stream).map(&:id) }.to(rest_events.map(&:id))
        end
        it 'adjusts stream revisions of the rest of events' do
          expect { subject }.to change { safe_read(stream).map(&:stream_revision) }.to((0...rest_events.size).to_a)
        end
        it { is_expected.to eq(true) }
      end

      it_behaves_like 'event gets deleted' do
        before do
          event
        end

        let(:rest_events) { [] }
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
          }.not_to change { safe_read(stream).map(&:id) }.from([event, *another_events].map(&:id))
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

    describe 'event deletion consistency' do
      let(:another_events) { PgEventstore.client.append_to_stream(stream, 3.times.map { PgEventstore::Event.new }) }
      let(:event) do
        event = PgEventstore::Event.new(data: { foo: :bar })
        PgEventstore.client.append_to_stream(stream, event)
      end
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:concurrent_deletion) { Thread.new { instance.call(event, force: force) } }

      before do
        event
        another_events
        # Slow down a transaction commit a bit to simulate concurrent deletion of the same event
        allow(transaction_queries).to receive(:transaction).and_wrap_original do |orig_meth, *args, **kwargs, &orig_blk|
          blk = proc do
            orig_blk.call.tap do
              sleep 1
            end
          end
          orig_meth.call(*args, **kwargs, &blk)
        end
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
