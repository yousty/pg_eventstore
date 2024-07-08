# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeederCommands::Restore do
  it { is_expected.to be_a(PgEventstore::SubscriptionFeederCommands::Base) }

  describe 'attributes' do
    it { is_expected.to have_attribute(:name).with_default_value('Restore') }
  end

  describe '.known_command?' do
    subject { described_class.known_command? }

    it { is_expected.to eq(true) }
  end

  describe '#exec_cmd' do
    subject { command.exec_cmd(subscription_feeder) }

    let(:command) { described_class.new }
    let(:subscription_feeder) { instance_spy(PgEventstore::SubscriptionFeeder) }

    it 'restores SubscriptionFeeder' do
      subject
      expect(subscription_feeder).to have_received(:restore)
    end
  end
end
