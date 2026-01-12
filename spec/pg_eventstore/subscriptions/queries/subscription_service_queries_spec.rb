# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionServiceQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#safe_global_position' do
    subject { instance.safe_global_position }

    context 'when safe position exists' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:event) do
        event = PgEventstore::Event.new
        PgEventstore.client.append_to_stream(stream, event)
      end

      before do
        event
      end

      it 'returns it' do
        is_expected.to eq(event.global_position)
      end
    end

    context 'when unsafe position exists' do
      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      # event1 gets created first, but its transaction finishes last, thus making event2 be in front of event1 for a
      # short period of time
      let(:event1) do
        Thread.new do
          event = PgEventstore::Event.new
          PgEventstore.client.multiple do
            PgEventstore.client.append_to_stream(stream1, event)
            sleep 0.2
          end
        end
      end
      let(:event2) do
        Thread.new do
          event = PgEventstore::Event.new
          PgEventstore.client.multiple do
            sleep 0.1
            PgEventstore.client.append_to_stream(stream2, event)
          end
        end
      end

      before do
        event1
        event2
      end

      after do
        event1.join
      end

      it 'returns default position' do
        event2.join
        is_expected.to eq(0)
      end
    end

    context 'when events_horizon does not exist' do
      it 'returns default position' do
        is_expected.to eq(0)
      end
    end

    context 'when events_horizon is created concurrently(regular event concurrency)' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:event) do
        event = PgEventstore::Event.new
        PgEventstore.client.append_to_stream(stream, event)
        PgEventstore.maintenance.delete_event(event)
        PgEventstore.connection.with do |conn|
          conn.exec('delete from events_horizon')
        end
        Thread.new do
          PgEventstore.client.multiple do
            PgEventstore.client.append_to_stream(stream, event)
            sleep 0.2
          end
        end
      end

      before do
        event
      end

      it 'returns safe position' do
        instance.safe_global_position
        event.join
        latest_position = PgEventstore.client.read(PgEventstore::Stream.all_stream).last.global_position
        is_expected.to eq(latest_position)
      end
    end

    context 'when events_horizon is created concurrently(another #safe_global_position concurrency)' do
      let(:safe_position1) { Thread.new { instance.safe_global_position } }
      let(:safe_position2) { Thread.new { instance.safe_global_position } }

      before do
        allow(instance).to receive(:init_events_horizon).and_wrap_original do |orig, *args, **kwargs, &blk|
          PgEventstore.client.multiple do
            orig.call(*args, **kwargs, &blk).tap do
              sleep 0.2
            end
          end
        end
      end

      it 'creates only one initial record with default position' do
        [safe_position1, safe_position2].each(&:join)
        total_count = PgEventstore.connection.with do |c|
          c.exec('select count(*) c from events_horizon').to_a.first['c']
        end
        aggregate_failures do
          expect(total_count).to eq(1)
          is_expected.to eq(0)
        end
      end
    end
  end

  describe '#events_horizon_present?' do
    subject { instance.events_horizon_present? }

    context 'when there is no positions' do
      it { is_expected.to eq(false) }
    end

    context 'when there is some position' do
      before do
        instance.init_events_horizon
      end

      it { is_expected.to eq(true) }
    end
  end

  describe '#init_events_horizon' do
    subject { instance.init_events_horizon }

    context 'when some position already exists' do
      before do
        stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
      end

      it 'does not create another one' do
        expect { subject }.not_to change {
          PgEventstore.connection.with do |conn|
            conn.exec('select count(*) c from events_horizon').to_a.first['c']
          end
        }.from(1)
      end
    end

    context 'when no position exists' do
      it 'creates default one' do
        aggregate_failures do
          expect { subject }.to change {
            PgEventstore.connection.with do |conn|
              conn.exec('select count(*) c from events_horizon').to_a.first['c']
            end
          }.by(1)
          pos = PgEventstore.connection.with do |c|
            c.exec('select global_position from events_horizon').to_a.first['global_position']
          end
          expect(pos).to eq(0)
        end
      end
    end
  end
end
