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

  describe '#call' do
    subject { instance.call(callbacks, raw_events, raw_events_cond) }

    let(:callbacks) { PgEventstore::Callbacks.new }
    let(:raw_events) { PgEventstore::SynchronizedArray.new }
    let(:raw_events_cond) { raw_events.new_cond }
    let(:on_process_cbx) do
      proc do |action, global_position|
        position_handler_before.call(global_position)
        action.call
        position_handler_after.call(global_position)
      end
    end
    let(:position_handler_before) { double('PositionHandlerBefore') }
    let(:position_handler_after) { double('PositionHandlerAfter') }

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
      let(:raw_events) { PgEventstore::SynchronizedArray.new([raw_event1, raw_event2]) }
      let(:raw_event1) { { 'global_position' => 123 } }
      let(:raw_event2) { { 'global_position' => 125 } }

      it 'does not sleep' do
        expect { subject }.to change { Time.now }.by(be_between(0, 0.01))
      end
      it 'runs :process callbacks for first event' do
        subject
        aggregate_failures do
          expect(position_handler_before).to have_received(:call).with(raw_event1['global_position'])
          expect(position_handler_after).to have_received(:call).with(raw_event1['global_position'])
        end
      end
      it 'does not run :process callbacks for second event' do
        subject
        aggregate_failures do
          expect(position_handler_before).not_to have_received(:call).with(raw_event2['global_position'])
          expect(position_handler_after).not_to have_received(:call).with(raw_event2['global_position'])
        end
      end
      it 'processes first event' do
        subject
        expect(raw_event_handler).to have_received(:call).with(raw_event1)
      end
      it 'does not process second event' do
        subject
        expect(raw_event_handler).not_to have_received(:call).with(raw_event2)
      end
      it 'removes processed event from the list' do
        expect { subject }.to change { raw_events }.to([raw_event2])
      end
    end

    context 'when handler raises an error' do
      let(:raw_events) { PgEventstore::SynchronizedArray.new([raw_event1, raw_event2]) }
      let(:raw_event1) { { 'global_position' => 123 } }
      let(:raw_event2) { { 'global_position' => 125 } }

      let(:handler) { proc { raise error_class, 'Oops!' } }
      let(:error_class) { Class.new(StandardError) }

      it 'does not sleep' do
        expect {
          begin
            subject
          rescue PgEventstore::WrappedException
          end
        }.to change { Time.now }.by(be_between(0, 0.01))
      end
      it 'does not process any event' do
        begin
          subject
        rescue PgEventstore::WrappedException
        end
        expect(raw_event_handler).not_to have_received(:call)
      end
      it 'runs only :before :process callbacks' do
        begin
          subject
        rescue PgEventstore::WrappedException
        end
        aggregate_failures do
          expect(position_handler_before).to have_received(:call).with(raw_event1['global_position'])
          expect(position_handler_after).not_to have_received(:call)
        end
      end
      it 'does not remove first event from the list' do
        expect {
          begin
            subject
          rescue PgEventstore::WrappedException
          end
        }.not_to change { raw_events }
      end
      # rubocop:disable RSpec/MultipleExpectations
      it 'raises the error' do
        expect { subject }.to raise_error(PgEventstore::WrappedException) do |error|
          aggregate_failures do
            expect(error.original_exception).to be_a(error_class)
            expect(error.original_exception.message).to eq('Oops!')
            expect(error.extra).to eq(global_position: raw_event1['global_position'])
          end
        end
      end
      # rubocop:enable RSpec/MultipleExpectations

      context 'when event which caused an exception is a link event' do
        let(:raw_event1) { { 'global_position' => 123, 'link' => { 'global_position' => 321 } } }

        # rubocop:disable RSpec/MultipleExpectations
        it 'raises the error with correct global position' do
          expect { subject }.to raise_error(PgEventstore::WrappedException) do |error|
            aggregate_failures do
              expect(error.original_exception).to be_a(error_class)
              expect(error.original_exception.message).to eq('Oops!')
              expect(error.extra).to eq(global_position: raw_event1['link']['global_position'])
            end
          end
        end
        # rubocop:enable RSpec/MultipleExpectations
      end
    end
  end
end
