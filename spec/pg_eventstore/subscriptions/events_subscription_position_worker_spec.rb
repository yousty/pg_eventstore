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
    let!(:index) do
      proc do
        PgEventstore.connection.with do |c|
          c.exec('select global_position, subscription_position from events_global_index')
        end.first
      end
    end

    before do
      reset_events_subscription_position
      allow(PgEventstore::EventsSubscriptionPositionWorkerHandlers).to receive(:sleep).and_wrap_original do
        sleep 0.1
      end
      PgEventstore.configure do |config|
        config.events_subscription_position_update_interval = 1.23
      end
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
  end
end
