# frozen_string_literal: true

RSpec.describe PgEventstore::EventsSubscriptionPositionWorker do
  let(:instance) { described_class.new(:default) }

  describe 'work' do
    subject do
      instance.start
      # let worker start and do the job
      sleep 0.1
    end

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let!(:event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
    let(:index) do
      proc do
        PgEventstore.connection.with do |c|
          c.exec('select global_position, subscription_position from event_subscription_positions')
        end.first
      end
    end
    let(:event_sposition_queries) { PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection) }

    before do
      reset_events_subscription_position
      allow(PgEventstore::EventsSubscriptionPositionWorkerHandlers).to receive(:sleep).and_wrap_original do
        sleep 0.1
      end
      PgEventstore.configure do |config|
        config.events_subscription_position_update_interval = 1.23
      end
      stub_const(
        'PgEventstore::EventSubscriptionPositionQueries::UNPROCESSED_POSITIONS_INDEX_SIZE_THRESHOLD',
        0
      )
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'updates events subscription position every config.events_subscription_position_update_interval seconds' do
      aggregate_failures do
        expect { subject }.to change {
          index.call
        }.to('global_position' => event.global_position, 'subscription_position' => 1)
        expect(PgEventstore::EventsSubscriptionPositionWorkerHandlers).to(
          have_received(:sleep).with(1.23).at_least(:once)
        )
      end
    end
    it 'reindexes unprocessed events' do
      idx_name = PgEventstore::EventSubscriptionPositionQueries::UNPROCESSED_POSITIONS_INDEX_NAME
      expect { subject; sleep 0.1; wait_for_reindex(idx_name) }.to change {
        event_sposition_queries.index_size(idx_name)
      }.to(MaintenanceHelpers::EMPTY_INDEX_SIZE)
    end
    it 'does not reindex too often' do
      idx_name = PgEventstore::EventSubscriptionPositionQueries::UNPROCESSED_POSITIONS_INDEX_NAME
      subject
      sleep 0.1
      wait_for_reindex(idx_name)
      # create dead tuples
      PgEventstore.connection.with do |conn|
        conn.exec('insert into event_subscription_positions_unprocessed (global_position) values (1), (2), (3)')
        conn.exec('delete from event_subscription_positions_unprocessed')
      end
      sleep 0.2
      expect(event_sposition_queries.index_size(idx_name)).to be > MaintenanceHelpers::EMPTY_INDEX_SIZE
    end
  end
end
