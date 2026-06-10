# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionServiceQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#assign_subscription_position' do
    subject { instance.assign_subscription_position }

    context 'when there are events to update' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let!(:event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
      let!(:index) do
        proc do
          PgEventstore.connection.with do |c|
            c.exec('select global_position, subscription_position from events_global_index')
          end.first
        end
      end

      context 'when there is another #assign_subscription_position running' do
        let(:concurrent_process) do
          Thread.new do
            PgEventstore.connection.with do |conn|
              conn.transaction do
                described_class.new(PgEventstore.connection).assign_subscription_position
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

        it { is_expected.to eq(nil) }
        it 'does not update indexes' do
          expect { subject }.not_to change {
            index.call
          }.from('global_position' => event.global_position, 'subscription_position' => nil)
        end
      end

      context 'when there are no concurrent #assign_subscription_position running' do
        before do
          reset_events_subscription_position
        end

        it 'returns the number of updated records' do
          is_expected.to eq(1)
        end
        it 'updates indexes' do
          expect { subject }.to change {
            index.call
          }.from('global_position' => event.global_position, 'subscription_position' => nil).
            to('global_position' => event.global_position, 'subscription_position' => 1)
        end
      end
    end
  end

  describe '#max_subscription_position' do
    subject { instance.max_subscription_position }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(5) { PgEventstore::Event.new }) }
    let(:indexes) { prepare_subscription_indexes(events) }

    before do
      indexes
    end

    it 'returns max global_position' do
      is_expected.to eq(indexes.last.subscription_position)
    end
  end
end
