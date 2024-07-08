# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeederCommands::StartAll do
  it { is_expected.to be_a(PgEventstore::SubscriptionFeederCommands::Base) }

  describe 'attributes' do
    it { is_expected.to have_attribute(:name).with_default_value('StartAll') }
  end

  describe '.known_command?' do
    subject { described_class.known_command? }

    it { is_expected.to eq(true) }
  end

  describe '#exec_cmd' do
    subject { command.exec_cmd(subscription_feeder) }

    let(:command) { described_class.new }
    let(:subscription_feeder) { instance_spy(PgEventstore::SubscriptionFeeder) }

    it 'performs start_all of SubscriptionFeeder' do
      subject
      expect(subscription_feeder).to have_received(:start_all)
    end
  end
end
