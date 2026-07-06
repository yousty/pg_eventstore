# frozen_string_literal: true

RSpec.describe PgEventstore::EventsProcessorConsumer::Single do
  let(:instance) { described_class.new(handler) }
  let(:handler) { proc { |raw_event| raw_event_handler.call(raw_event) } }
  let(:raw_event_handler) { double('RawEventHandler') }

  before do
    allow(raw_event_handler).to receive(:call)
  end

  it 'implements EventsProcessorConsumer' do
    expect(instance).to be_a(PgEventstore::EventsProcessorConsumer)
  end

  describe '#clear_unprocessed_events' do
    subject { instance.clear_unprocessed_events }

    before do
      instance.instance_variable_set(:@last_unprocessed_event, { 'global_position' => 1 })
    end

    it { expect { subject }.to change { instance.instance_variable_get(:@last_unprocessed_event) }.to(nil) }
  end

  describe '#call' do
    subject { instance.call(callbacks, repository, repository_cond) }

    let(:callbacks) { PgEventstore::Callbacks.new }
    let(:repository) { PgEventstore::Chunks::Repository.new }
    let(:repository_cond) { repository.new_cond }
    let(:on_process_cbx) do
      proc do |action, global_position|
        position_handler_before.call(global_position)
        action.call
        position_handler_after.call(global_position)
      end
    end
    let(:position_handler_before) { double('PositionHandlerBefore') }
    let(:position_handler_after) { double('PositionHandlerAfter') }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    before do
      callbacks.define_callback(:process, :around, on_process_cbx)
      allow(position_handler_before).to receive(:call)
      allow(position_handler_after).to receive(:call)
    end

    context 'when no events are given' do
      it 'sleeps for .5 seconds' do
        expect { subject }.to change { Time.now }.by(be_between(0.5, 0.51))
      end
      it 'does not run :process callbacks' do
        subject
        aggregate_failures do
          expect(position_handler_before).not_to have_received(:call)
          expect(position_handler_after).not_to have_received(:call)
        end
      end
      it 'does not process any event' do
        subject
        expect(raw_event_handler).not_to have_received(:call)
      end
    end

    context 'when there are some events' do
      let(:event1) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
      let(:event2) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
      let(:indexes) { prepare_subscription_indexes([event1, event2]) }
      let(:chunk) { create_subscription_index_chunk(indexes) }

      before do
        repository.add_chunk(chunk)
      end

      it 'does not sleep' do
        expect { subject }.to change { Time.now }.by(be_between(0, 0.05))
      end
      it 'runs :process callbacks for first event' do
        subject
        aggregate_failures do
          expect(position_handler_before).to have_received(:call).with(indexes.first.subscription_position)
          expect(position_handler_after).to have_received(:call).with(indexes.first.subscription_position)
        end
      end
      it 'does not run :process callbacks for second event' do
        subject
        aggregate_failures do
          expect(position_handler_before).not_to have_received(:call).with(indexes.last.subscription_position)
          expect(position_handler_after).not_to have_received(:call).with(indexes.last.subscription_position)
        end
      end
      it 'processes first event' do
        raw_event1 = a_hash_including('global_position' => event1.global_position, 'id' => event1.id)
        subject
        expect(raw_event_handler).to have_received(:call).with(raw_event1)
      end
      it 'does not process second event' do
        raw_event2 = a_hash_including('global_position' => event2.global_position, 'id' => event2.id)
        subject
        expect(raw_event_handler).not_to have_received(:call).with(raw_event2)
      end
      it 'removes processed index from chunk' do
        expect { subject }.to change { chunk.size }.by(-1)
      end
      it 'clears @last_unprocessed_event' do
        unprocessed_event = PgEventstore::Chunks::SubscriptionEventsIndexChunk::RawEventWithCommitPosition.new(
          attributes: {}, subscription_position: 1
        )
        instance.instance_variable_set(:@last_unprocessed_event, unprocessed_event)
        expect { subject }.to change { instance.instance_variable_get(:@last_unprocessed_event) }.to(nil)
      end
    end

    context 'when checkpoint event is consumed' do
      let(:chunk) { PgEventstore::Chunks::SubscriptionCheckpointChunk.new(position) }
      let(:position) { 123 }
      let(:checkpoint_handler) { double('Checkpoint Handler') }

      before do
        repository.add_chunk(chunk)
        allow(checkpoint_handler).to receive(:call)
        callbacks.define_callback(:checkpoint, :before, proc { |pos| checkpoint_handler.call(pos) })
      end

      it 'does not call handler' do
        subject
        expect(raw_event_handler).not_to have_received(:call)
      end
      it 'runs :checkpoint callback' do
        subject
        expect(checkpoint_handler).to have_received(:call).with(position)
      end
    end

    context 'when handler raises an error' do
      let(:event1) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
      let(:event2) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
      let(:indexes) { prepare_subscription_indexes([event1, event2]) }
      let(:chunk) { create_subscription_index_chunk(indexes) }

      let(:handler) { proc { raise error_class, 'Oops!' } }
      let(:error_class) { Class.new(StandardError) }

      before do
        repository.add_chunk(chunk)
      end

      it 'does not sleep' do
        expect {
          begin
            subject
          rescue PgEventstore::WrappedException
          end
        }.to change { Time.now }.by(be_between(0, 0.05))
      end
      it 'runs only :before :process callbacks' do
        begin
          subject
        rescue PgEventstore::WrappedException
        end
        aggregate_failures do
          expect(position_handler_before).to have_received(:call).with(indexes.first.subscription_position)
          expect(position_handler_after).not_to have_received(:call)
        end
      end
      it 'removes unprocessed index from chunk' do
        expect {
          begin
            subject
          rescue PgEventstore::WrappedException
          end
        }.to change { chunk.size }.by(-1)
      end
      it 'persists unprocessed event into @last_unprocessed_event' do
        unprocessed_event_attrs = a_hash_including('global_position' => event1.global_position, 'id' => event1.id)
        expect {
          begin
            subject
          rescue PgEventstore::WrappedException
          end
        }.to change { instance.instance_variable_get(:@last_unprocessed_event)&.attributes }.to(unprocessed_event_attrs)
      end
      # rubocop:disable RSpec/MultipleExpectations
      it 'raises the error' do
        expect { subject }.to raise_error(PgEventstore::WrappedException) do |error|
          aggregate_failures do
            expect(error.original_exception).to be_a(error_class)
            expect(error.original_exception.message).to eq('Oops!')
            expect(error.extra).to eq(global_position: indexes.first.subscription_position)
          end
        end
      end
      # rubocop:enable RSpec/MultipleExpectations

      context 'when event which caused an exception is a link event' do
        let(:event1) { PgEventstore.client.link_to(stream, event2) }
        let(:chunk) { create_subscription_index_chunk(indexes, resolve_link_tos: true) }

        # rubocop:disable RSpec/MultipleExpectations
        it 'raises the error with correct global position' do
          expect { subject }.to raise_error(PgEventstore::WrappedException) do |error|
            aggregate_failures do
              expect(error.original_exception).to be_a(error_class)
              expect(error.original_exception.message).to eq('Oops!')
              expect(error.extra).to eq(global_position: indexes.first.subscription_position)
            end
          end
        end
        # rubocop:enable RSpec/MultipleExpectations
      end
    end
  end
end
