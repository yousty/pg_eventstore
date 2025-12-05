# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionPositionEvaluation do
  let(:instance) { described_class.new(config_name: :default, filter_options: filter_options) }
  let(:filter_options) { {} }

  describe '#evaluate' do
    subject { instance.evaluate(position_to_evaluate) }

    let(:position_to_evaluate) { 0 }

    after do
      instance.stop_evaluation&.join
    end

    it { is_expected.to eq(instance) }
    it 'does not re-evaluate the position on consecutive calls with the same position_to_evaluate argument' do
      aggregate_failures do
        expect { subject }.to change {
          dv(instance).deferred_wait(timeout: 0.2, &:last_safe_position).last_safe_position
        }.from(nil).to(0)
        expect(instance.evaluate(position_to_evaluate).last_safe_position).to eq(0)
      end
    end

    shared_examples 'safe position' do
      it 'marks the position as safe' do
        expect { subject }.to change {
          dv(instance).deferred_wait(timeout: timeout, &:safe?).safe?
        }.from(false).to(true)
      end
    end

    shared_examples 'wait for the current transaction' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:event) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo'))
      end

      before do
        event
        @publisher = Thread.new do
          PgEventstore.client.multiple do
            PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo'))
            sleep 0.6
          end
        end
        # let the thread time to start
        sleep 0.1
      end

      after do
        @publisher.join
      end

      it 'waits for that event to be published before returning the position' do
        aggregate_failures do
          time = Benchmark.realtime do
            expect { subject }.to change {
              dv(instance).deferred_wait(timeout: 1, &:last_safe_position).last_safe_position
            }.from(nil).to(event.global_position)
          end
          expect(time).to(
            be > 0.5,
            <<~TEXT
              Evaluator should wait for the currently running transactions to finish. Waited for: \
              #{time.round(3).inspect} seconds.
            TEXT
          )
        end
      end
      it_behaves_like 'safe position' do
        let(:timeout) { 1 }
      end
    end

    shared_examples 'does not wait for the current transaction' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:event) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo'))
      end

      before do
        event
        @publisher = Thread.new do
          PgEventstore.client.multiple do
            PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Bar'))
            sleep 0.6
          end
        end
        # let the thread time to start
        sleep 0.1
      end

      after do
        @publisher.join
      end

      it 'does not wait for that event to be published before returning the position' do
        aggregate_failures do
          time = Benchmark.realtime do
            expect { subject }.to change {
              dv(instance).deferred_wait(timeout: 0.2, &:last_safe_position).last_safe_position
            }.from(nil).to(event.global_position)
          end
          expect(time).to(
            be < 0.2,
            <<~TEXT
              Evaluator should not wait for the currently running transactions to finish. Waited for: \
              #{time.round(3).inspect} seconds.
            TEXT
          )
        end
      end
      it_behaves_like 'safe position' do
        let(:timeout) { 0.2 }
      end
    end

    context 'when there are no filters' do
      context 'when there are no events' do
        it 'returns calculates safe position to 0' do
          expect { subject }.to change {
            dv(instance).deferred_wait(timeout: 0.2, &:last_safe_position).last_safe_position
          }.from(nil).to(0)
        end
        it_behaves_like 'safe position' do
          let(:timeout) { 0.2 }
        end
      end

      context 'when there are events' do
        let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
        let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }
        let(:stream3) { PgEventstore::Stream.new(context: 'BazCtx', stream_name: 'Baz', stream_id: '1') }

        let(:event1) do
          PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'Foo'))
        end
        let(:event2) do
          PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'Bar'))
        end
        let(:event3) do
          PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new(type: 'Baz'))
        end

        before do
          event1
          event2
          event3
        end

        it 'calculates safe position to the position of latest event' do
          expect { subject }.to change {
            dv(instance).deferred_wait(timeout: 0.2, &:last_safe_position).last_safe_position
          }.from(nil).to(event3.global_position)
        end
        it_behaves_like 'safe position' do
          let(:timeout) { 0.2 }
        end
      end

      context 'when at the moment of the evaluation there is some transaction producing new event' do
        it_behaves_like 'wait for the current transaction'
      end
    end

    context 'when there are filters' do
      let(:filter_options) { { event_types: ['Foo'], streams: { context: ['FooCtx'] } } }

      context 'when there are no events' do
        it 'returns calculates safe position to 0' do
          expect { subject }.to change {
            dv(instance).deferred_wait(timeout: 0.2, &:last_safe_position).last_safe_position
          }.from(nil).to(0)
        end
        it_behaves_like 'safe position' do
          let(:timeout) { 0.2 }
        end
      end

      context 'when there are events' do
        let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
        let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }
        let(:stream3) { PgEventstore::Stream.new(context: 'BazCtx', stream_name: 'Baz', stream_id: '1') }

        let(:event1) do
          PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'Foo'))
        end
        let(:event2) do
          PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'Bar'))
        end
        let(:event3) do
          PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'Bar'))
        end
        let(:event4) do
          PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new(type: 'Baz'))
        end

        before do
          event1
          event2
          event3
          event4
        end

        it 'calculates safe position to the position of latest event matching the filter' do
          expect { subject }.to change {
            dv(instance).deferred_wait(timeout: 0.2, &:last_safe_position).last_safe_position
          }.from(nil).to(event1.global_position)
        end
        it_behaves_like 'safe position' do
          let(:timeout) { 0.2 }
        end
      end

      context 'when at the moment of the evaluation there is a transaction producing new event matching the filter' do
        it_behaves_like 'wait for the current transaction'
      end

      descr = <<~TEXT
        when at the moment of the evaluation there is a transaction producing new event that does not match the filter
      TEXT
      context descr do
        it_behaves_like 'does not wait for the current transaction'
      end
    end

    context 'when connection lose happens during the evaluation' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:event) do
        PgEventstore::Event.new(type: 'Foo')
      end
      let(:disconnect_simulator) do
        proc do
          PgEventstore.configure do |config|
            config.pg_uri = 'postgres://127.0.0.1:1234/eventstore'
          end
        end
      end

      before do
        @publisher = Thread.new do
          PgEventstore.client.multiple do
            PgEventstore.client.append_to_stream(stream, event)
            loop do
              sleep 0.05
              break if Thread.current[:terminate]
            end
          end
        end
        # let the thread time to start
        sleep 0.1
      end

      after do
        @publisher[:terminate] = true
        @publisher.join
      end

      it 'resets #position_to_evaluate' do
        subject
        expect { disconnect_simulator.call }.to change {
          dv(instance).deferred_wait(timeout: 0.5) {
            _1.send(:position_to_evaluate).nil?
          }.send(:position_to_evaluate)
        }.to(nil)
      end
      it 'resets #last_safe_position' do
        subject
        instance.send(:last_safe_position=, 1)
        expect { disconnect_simulator.call }.to change {
          dv(instance).deferred_wait(timeout: 0.5) {
            _1.last_safe_position.nil?
          }.last_safe_position
        }.to(nil)
      end
      it 'resets #position_is_safe' do
        subject
        instance.send(:position_is_safe=, true)
        expect { disconnect_simulator.call }.to change {
          dv(instance).deferred_wait(timeout: 0.5) {
            _1.send(:position_is_safe).nil?
          }.send(:position_is_safe)
        }.to(nil)
      end
    end
  end
end
