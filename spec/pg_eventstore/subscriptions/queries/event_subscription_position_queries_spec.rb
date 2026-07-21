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
      [{ 'global_position' => 1, 'stream_revision' => 0 }, { 'global_position' => 3, 'stream_revision' => 0 }]
    end

    it 'creates unprocessed positions' do
      expect { subject }.to change {
        PgEventstore.connection.with { |c| c.exec('select * from event_subscription_positions_unprocessed') }
      }.to([{ 'global_position' => 1 }, { 'global_position' => 3 }])
    end
  end

  describe '#reindex_unprocessed_positions', timecop: Time.utc(2026, 1, 1, 12, 0, 0) do
    subject { instance.reindex_unprocessed_positions }

    let(:task_name) { 'reindex_unprocessed_positions' }
    let(:now) { Time.now.utc }
    let(:performed_at) { now - described_class::REINDEX_PERIOD + 1 }
    let(:expired_performed_at) { now - described_class::REINDEX_PERIOD - 1 }
    let(:locked_at) { now - described_class::UNPROCESSED_POSITIONS_LOCK_EXPIRES_IN + 1 }
    let(:expired_locked_at) { now - described_class::UNPROCESSED_POSITIONS_LOCK_EXPIRES_IN - 1 }
    let(:maintenance_task) do
      proc do
        PgEventstore.connection.with do |conn|
          conn.exec_params(
            'select * from maintenance_tasks where task_name = $1',
            [task_name]
          ).first
        end
      end
    end
    let(:create_maintenance_task) do
      proc do |locked_at: nil, performed_at: nil|
        PgEventstore.connection.with do |conn|
          conn.exec_params(
            'insert into maintenance_tasks (task_name, locked_at, performed_at) values ($1, $2, $3)',
            [task_name, locked_at, performed_at]
          )
        end
      end
    end

    before do
      # create dead tuples
      PgEventstore.connection.with do |conn|
        conn.exec('insert into event_subscription_positions_unprocessed (global_position) values (1), (2), (3)')
        conn.exec('delete from event_subscription_positions_unprocessed')
      end
      stub_const("#{described_class}::UNPROCESSED_POSITIONS_INDEX_SIZE_THRESHOLD", 0)
    end

    shared_examples 'reindex' do
      it 'shrinks the index' do
        expect { subject; wait_for_reindex(described_class::UNPROCESSED_POSITIONS_INDEX_NAME) }.to change {
          instance.index_size(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
        }.to(MaintenanceHelpers::EMPTY_INDEX_SIZE)
      end
      it 'returns the time of next reindex' do
        is_expected.to eq(now + described_class::REINDEX_PERIOD)
      end
      it 'marks task as performed' do
        expect { subject }.to change {
          maintenance_task.call
        }.to(include('locked_at' => nil, 'performed_at' => now))
      end
    end

    context 'when maintenance task was recently performed' do
      before do
        create_maintenance_task.call(performed_at: performed_at)
      end

      it 'returns the next reindex time' do
        is_expected.to eq(performed_at + described_class::REINDEX_PERIOD)
      end
      it 'does not acquire the task lock' do
        expect { subject }.not_to change {
          maintenance_task.call['locked_at']
        }.from(nil)
      end
      it 'does not reindex' do
        expect { subject; wait_for_reindex(described_class::UNPROCESSED_POSITIONS_INDEX_NAME) }.not_to change {
          instance.index_size(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
        }
      end
    end

    context 'when maintenance task is locked and the lock is not expired' do
      before do
        create_maintenance_task.call(locked_at: locked_at, performed_at: expired_performed_at)
      end

      it 'returns the next lock retry time' do
        is_expected.to eq(locked_at + described_class::UNPROCESSED_POSITIONS_LOCK_EXPIRES_IN)
      end
      it 'keeps the existing lock' do
        expect { subject }.not_to change {
          maintenance_task.call['locked_at']
        }.from(locked_at)
      end
      it 'does not reindex' do
        expect { subject; wait_for_reindex(described_class::UNPROCESSED_POSITIONS_INDEX_NAME) }.not_to change {
          instance.index_size(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
        }
      end
    end

    context 'when maintenance task is locked and the lock is expired' do
      before do
        create_maintenance_task.call(locked_at: expired_locked_at, performed_at: expired_performed_at)
      end

      it_behaves_like 'reindex'
    end

    context 'when maintenance task exists and is unlocked' do
      before do
        create_maintenance_task.call(performed_at: expired_performed_at)
      end

      it_behaves_like 'reindex'
    end

    context 'when maintenance task does not exist' do
      it 'creates a maintenance task' do
        expect { subject }.to change { maintenance_task.call }.from(nil).to(
          'task_name' => task_name,
          'locked_at' => nil,
          'performed_at' => now
        )
      end
      it 'shrinks the index' do
        expect { subject; wait_for_reindex(described_class::UNPROCESSED_POSITIONS_INDEX_NAME) }.to change {
          instance.index_size(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
        }.to(MaintenanceHelpers::EMPTY_INDEX_SIZE)
      end
      it 'returns the time of next reindex' do
        is_expected.to eq(now + described_class::REINDEX_PERIOD)
      end
    end

    context 'when unprocessed positions index size is at threshold' do
      before do
        create_maintenance_task.call(performed_at: expired_performed_at)
        index_size = instance.index_size(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
        stub_const(
          "#{described_class}::UNPROCESSED_POSITIONS_INDEX_SIZE_THRESHOLD",
          index_size
        )
      end

      it 'does not reindex' do
        expect { subject; wait_for_reindex(described_class::UNPROCESSED_POSITIONS_INDEX_NAME) }.not_to change {
          instance.index_size(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
        }
      end
      it 'marks task as performed' do
        expect { subject }.to change {
          maintenance_task.call
        }.to(include('locked_at' => nil, 'performed_at' => now))
      end
      it 'returns the time of next reindex' do
        is_expected.to eq(now + described_class::REINDEX_PERIOD)
      end
    end

    context 'when a concurrent process creates the maintenance task first' do
      let(:release) { Thread::Queue.new }
      let(:synchronizer) { Thread::Queue.new }
      let(:concurrent_process) do
        Thread.new do
          PgEventstore.connection.with do |conn|
            conn.transaction do
              conn.exec_params(
                'insert into maintenance_tasks (task_name, locked_at) values ($1, $2)',
                [task_name, now]
              )
              synchronizer.push(:inserted)
              release.pop
            end
          end
        end
      end

      before do
        concurrent_process
        synchronizer.pop
      end

      after do
        release.push(:release)
        concurrent_process.join
      end

      it 'does not reindex' do
        subject_thread = Thread.new { subject }
        sleep 0.1
        release.push(:release)

        aggregate_failures do
          expect {
            subject_thread.join; wait_for_reindex(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
          }.not_to change {
            instance.index_size(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
          }
          expect(subject_thread.value).to eq(nil)
        end
      end
    end

    context 'when a concurrent process acquires the lock' do
      let(:release) { Thread::Queue.new }
      let(:synchronizer) { Thread::Queue.new }
      let(:concurrent_process) do
        Thread.new do
          PgEventstore.connection.with do |conn|
            conn.transaction do
              conn.exec_params(
                'update maintenance_tasks set locked_at = $1 where task_name = $2',
                [Time.now.utc - 10, task_name]
              )
              synchronizer.push(:updated)
              release.pop
            end
          end
        end
      end

      before do
        create_maintenance_task.call(performed_at: expired_performed_at)
        concurrent_process
        synchronizer.pop
      end

      after do
        concurrent_process.exit
      end

      it 'does not reindex' do
        subject_thread = Thread.new { subject }
        sleep 0.1
        release.push(:release)

        aggregate_failures do
          expect {
            subject_thread.join; wait_for_reindex(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
          }.not_to change {
            instance.index_size(described_class::UNPROCESSED_POSITIONS_INDEX_NAME)
          }
          expect(subject_thread.value).to eq(nil)
        end
      end
    end
  end
end
