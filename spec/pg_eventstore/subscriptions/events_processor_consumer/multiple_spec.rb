# frozen_string_literal: true

RSpec.describe PgEventstore::EventsProcessorConsumer::Multiple do
  let(:instance) { described_class.new(handler) }
  let(:handler) { proc { |raw_events| raw_events_handler.call(raw_events) } }
  let(:raw_events_handler) { double('RawEventsHandler') }

  before do
    allow(raw_events_handler).to receive(:call)
  end

  it 'implements EventsProcessorConsumer' do
    expect(instance).to be_a(PgEventstore::EventsProcessorConsumer)
  end

  describe '#clear_unprocessed_events' do
    subject { instance.clear_unprocessed_events }

    before do
      instance.instance_variable_set(:@last_unprocessed_events, [{ 'global_position' => 1 }])
    end

    it { expect { subject }.to change { instance.instance_variable_get(:@last_unprocessed_events) }.to(nil) }
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
        expect(raw_events_handler).not_to have_received(:call)
      end
    end

    context 'when there are some events' do
      let(:raw_indexes) { [raw_index1, raw_index2] }
      let(:raw_index1) { { 'global_position' => 123, 'event_type_partition_id' => 2 } }
      let(:raw_index2) { { 'global_position' => 125, 'event_type_partition_id' => 2 } }
      let(:chunk) { EventIndexesChunk.create_indexes(raw_indexes) }

      before do
        repository.add_chunk(chunk)
      end

      it 'does not sleep' do
        expect { subject }.to change { Time.now }.by(be_between(0, 0.01))
      end
      it 'runs :process callbacks for the last event' do
        subject
        aggregate_failures do
          expect(position_handler_before).to have_received(:call).with(raw_index2['global_position'])
          expect(position_handler_after).to have_received(:call).with(raw_index2['global_position'])
        end
      end
      it 'does not run :process callbacks for first event' do
        subject
        aggregate_failures do
          expect(position_handler_before).not_to have_received(:call).with(raw_index1['global_position'])
          expect(position_handler_after).not_to have_received(:call).with(raw_index1['global_position'])
        end
      end
      it 'processes events' do
        subject
        expect(raw_events_handler).to(
          have_received(:call).
            with(
              [
                { 'global_position' => raw_index1['global_position'], 'id' => '00000000-0000-0000-0000-000000000001' },
                { 'global_position' => raw_index2['global_position'], 'id' => '00000000-0000-0000-0000-000000000002' },
              ]
            )
        )
      end
      it 'drains chunk' do
        expect { subject }.to change { chunk.size }.to(0)
      end
      it 'clears @last_unprocessed_events' do
        instance.instance_variable_set(:@last_unprocessed_events, [{ 'global_position' => 1 }])
        expect { subject }.to change { instance.instance_variable_get(:@last_unprocessed_events) }.to(nil)
      end
    end

    context 'when handler raises an error' do
      let(:raw_indexes) { [raw_index1, raw_index2] }
      let(:raw_index1) { { 'global_position' => 123, 'event_type_partition_id' => 2 } }
      let(:raw_index2) { { 'global_position' => 125, 'event_type_partition_id' => 2 } }
      let(:chunk) { EventIndexesChunk.create_indexes(raw_indexes) }

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
        }.to change { Time.now }.by(be_between(0, 0.01))
      end
      it 'runs only :before :process callbacks' do
        begin
          subject
        rescue PgEventstore::WrappedException
        end
        aggregate_failures do
          expect(position_handler_before).to have_received(:call).with(raw_index2['global_position'])
          expect(position_handler_after).not_to have_received(:call)
        end
      end
      it 'drains chunk' do
        expect {
          begin
            subject
          rescue PgEventstore::WrappedException
          end
        }.to change { chunk.size }.to(0)
      end
      it 'persists unprocessed events into @last_unprocessed_events' do
        unprocessed_events = [
          { 'global_position' => raw_index1['global_position'], 'id' => '00000000-0000-0000-0000-000000000001' },
          { 'global_position' => raw_index2['global_position'], 'id' => '00000000-0000-0000-0000-000000000002' },
        ]
        expect {
          begin
            subject
          rescue PgEventstore::WrappedException
          end
        }.to change { instance.instance_variable_get(:@last_unprocessed_events) }.to(unprocessed_events)
      end
      # rubocop:disable RSpec/MultipleExpectations
      it 'raises the error' do
        expect { subject }.to raise_error(PgEventstore::WrappedException) do |error|
          aggregate_failures do
            expect(error.original_exception).to be_a(error_class)
            expect(error.original_exception.message).to eq('Oops!')
            expect(error.extra).to eq(global_positions: [raw_index1['global_position'], raw_index2['global_position']])
          end
        end
      end
      # rubocop:enable RSpec/MultipleExpectations

      context 'when event which caused an exception is a link event' do
        let(:chunk) { EventIndexesChunk.create_indexes([raw_index], make_links: true, links_starting_id: 321) }
        let(:raw_index) { { 'global_position' => 123, 'event_type_partition_id' => 2 } }

        # rubocop:disable RSpec/MultipleExpectations
        it 'raises the error with correct global positions' do
          expect { subject }.to raise_error(PgEventstore::WrappedException) do |error|
            aggregate_failures do
              expect(error.original_exception).to be_a(error_class)
              expect(error.original_exception.message).to eq('Oops!')
              expect(error.extra).to(
                eq(global_positions: [321])
              )
            end
          end
        end
        # rubocop:enable RSpec/MultipleExpectations
      end
    end
  end
end
