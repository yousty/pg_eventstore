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
end
