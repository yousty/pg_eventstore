# frozen_string_literal: true

RSpec.describe PgEventstore::EventSubscriptionPositionQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#assign_subscription_position' do
    subject { instance.assign_subscription_position }

    context 'when there are events to update' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let!(:event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
      let(:unprocessed_position) do
        proc do
          PgEventstore.connection.with do |c|
            c.exec('select global_position from event_subscription_positions_unprocessed')
          end.first
        end
      end
      let(:processed_position) do
        proc do
          PgEventstore.connection.with do |c|
            c.exec('select global_position, subscription_position from event_subscription_positions')
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
        it 'does not remove unprocessed positions' do
          expect { subject }.not_to change {
            unprocessed_position.call
          }.from('global_position' => event.global_position)
        end
        it 'does not create processed positions' do
          expect { subject }.not_to change { processed_position.call }.from(nil)
        end
      end

      context 'when there are no concurrent #assign_subscription_position running' do
        before do
          reset_events_subscription_position
        end

        it 'returns the number of processed records' do
          is_expected.to eq(1)
        end
        it 'removes unprocessed positions' do
          expect { subject }.to change {
            unprocessed_position.call
          }.from('global_position' => event.global_position).to(nil)
        end
        it 'creates processed positions' do
          expect { subject }.to change {
            processed_position.call
          }.from(nil).to('global_position' => event.global_position, 'subscription_position' => 1)
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

  describe '#subscription_positions_from_db' do
    subject do
      instance.subscription_positions_from_db([non_existing_event, persisted_event, event_with_subscription_positions])
    end

    let(:persisted_event) do
      stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
      PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
    end
    let(:non_existing_event) do
      PgEventstore::Event.new(global_position: -1)
    end
    let(:event_with_subscription_positions) do
      stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
      PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
    end

    before do
      event_with_subscription_positions
      instance.assign_subscription_position
      persisted_event
    end

    it 'returns global_position-to-subscription_position map' do
      is_expected.to(match(event_with_subscription_positions.global_position => kind_of(Integer)))
    end
  end

  describe '#create_unprocessed_positions' do
    subject { instance.create_unprocessed_positions(raw_events) }

    let(:raw_events) do
      [{ 'global_position' => 1, 'stream_revision' => 0, 'global_position' => 3, 'stream_revision' => 0 }]
    end

    it 'creates unprocessed positions' do
      expect { subject }.to change {
        PgEventstore.connection.with { |c| c.exec('select * from event_subscription_positions_unprocessed') }
      }.to([{ 'global_position' => 1, 'global_position' => 3 }])
    end
  end
end
