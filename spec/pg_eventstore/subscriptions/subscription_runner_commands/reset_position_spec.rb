# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunnerCommands::ResetPosition do
  it { is_expected.to be_a(PgEventstore::SubscriptionRunnerCommands::Base) }

  describe 'attributes' do
    it { is_expected.to have_attribute(:name).with_default_value('ResetPosition') }
  end

  describe '.known_command?' do
    subject { described_class.known_command? }

    it { is_expected.to eq(true) }
  end

  describe '.parse_data' do
    subject { described_class.parse_data(data) }

    let(:data) { { 'position' => 123 } }

    context 'when position is given' do
      it { is_expected.to eq({ 'position' => 123 }) }
    end

    context 'when string representation of position is given' do
      let(:data) { { 'position' => '123' } }

      it { is_expected.to eq({ 'position' => 123 }) }
    end

    context 'when incorrect position is given' do
      let(:data) { { 'position' => nil } }

      it 'raises error' do
        expect { subject }.to raise_error(TypeError, "can't convert nil into Integer")
      end
    end
  end

  describe '#exec_cmd' do
    subject { command.exec_cmd(subscription_runner) }

    let(:command) { described_class.new(data: { 'position' => position }) }
    let(:subscription_runner) do
      PgEventstore::SubscriptionRunner.new(stats: stats, events_processor: events_processor, subscription: subscription)
    end

    let(:position) { 123 }
    let(:stats) { PgEventstore::SubscriptionHandlerPerformance.new }
    let(:events_processor) { PgEventstore::EventsProcessor.new(handler) }
    let(:subscription) do
      SubscriptionsHelper.create_with_connection(last_chunk_greatest_position: 321, total_processed_events: 120)
    end
    let(:handler) { proc {} }

    before do
      # Feeding is only available when runner is running. So start it, put some events into a chunk and stop it.
      subscription_runner.start
      sleep 0.1
      subscription_runner.feed([{ 'global_position' => 1 }])
      subscription_runner.stop_async.wait_for_finish
    end

    it "sets subscription#current_position to the given position" do
      expect { subject }.to change { subscription.reload.current_position }.to(position)
    end
    it "resets subscription#last_chunk_greatest_position" do
      expect { subject }.to change { subscription.reload.last_chunk_greatest_position }.to(nil)
    end
    it "resets subscription#total_processed_events" do
      expect { subject }.to change { subscription.reload.total_processed_events }.to(0)
    end
    it "resets current runner's chunk" do
      expect { subject }.to change { events_processor.events_left_in_chunk }.from(1).to(0)
    end
  end
end
