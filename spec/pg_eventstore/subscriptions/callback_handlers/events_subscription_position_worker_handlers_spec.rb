# frozen_string_literal: true

RSpec.describe PgEventstore::EventsSubscriptionPositionWorkerHandlers do
  it { is_expected.to be_a(PgEventstore::Extensions::CallbackHandlersExtension) }

  describe '.assign_subscription_position' do
    subject { described_class.assign_subscription_position(event_subscription_position_queries, update_interval) }

    let(:event_subscription_position_queries) do
      PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection)
    end
    let(:update_interval) { 2.1 }

    before do
      allow(described_class).to receive(:sleep)
    end

    context 'when assigning query is already blocked by another process' do
      let(:concurrent_process) do
        Thread.new do
          PgEventstore.connection.with do |conn|
            conn.transaction do
              event_subscription_position_queries.assign_subscription_position
              synchronizer.push(:sig)
              sleep 1
            end
          end
        end
      end
      let(:synchronizer) { Thread::Queue.new }

      before do
        concurrent_process
        synchronizer.pop
      end

      after do
        concurrent_process.exit
      end

      it 'waits for the given interval' do
        subject
        expect(described_class).to have_received(:sleep).with(update_interval)
      end
    end

    context 'when assigning query does not update any records' do
      it 'waits for the given interval' do
        subject
        expect(described_class).to have_received(:sleep).with(update_interval)
      end
    end

    context 'when assigning query updates some records' do
      before do
        stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
        PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new })
      end

      context 'when the number of updated records is less than max number of records to update per run' do
        it 'waits for the given interval' do
          subject
          expect(described_class).to have_received(:sleep).with(update_interval)
        end
      end

      context 'when the number of updated records is greater than max number of records to update per run' do
        before do
          stub_const(
            'PgEventstore::EventSubscriptionPositionQueries::MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION',
            1
          )
        end

        it 'does not wait for the given interval' do
          subject
          expect(described_class).not_to have_received(:sleep)
        end
      end
    end
  end

  describe '.reindex' do
    subject { described_class.reindex(event_sposition_queries, next_reindex_at) }

    let(:event_sposition_queries) { PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection) }
    let(:next_reindex_at) { PgEventstore::EventsSubscriptionPositionWorker::ReindexTime.new(time:) }
    let(:time) { Time.now.utc - 1 }

    before do
      allow(event_sposition_queries).to receive(:reindex_unprocessed_positions).and_call_original
    end

    context 'when reindex was performed recently' do
      let(:time) { Time.now.utc + 10 }

      it 'does not run another one' do
        subject
        expect(event_sposition_queries).not_to have_received(:reindex_unprocessed_positions)
      end
      it 'does not update next_reindex_at' do
        expect { subject }.not_to change { next_reindex_at.time }
      end
    end

    context 'when reindex was performed long time ago' do
      it 'runs reindex' do
        subject
        expect(event_sposition_queries).to have_received(:reindex_unprocessed_positions)
      end
      it 'updates next_reindex_at' do
        expect { subject }.to change { next_reindex_at.time }.to be > Time.now.utc + 1
      end
    end

    context 'when reindex was not performed at all' do
      let(:time) { nil }

      it 'runs reindex' do
        subject
        expect(event_sposition_queries).to have_received(:reindex_unprocessed_positions)
      end
      it 'updates next_reindex_at' do
        expect { subject }.to change { next_reindex_at.time }.to be > Time.now.utc + 1
      end
    end

    context 'when reindex action fails' do
      before do
        allow(event_sposition_queries).to receive(:reindex_unprocessed_positions).and_return(nil)
      end

      it 'runs reindex' do
        subject
        expect(event_sposition_queries).to have_received(:reindex_unprocessed_positions)
      end
      it 'does not update next_reindex_at' do
        expect { subject }.not_to change { next_reindex_at.time }
      end
    end
  end
end
