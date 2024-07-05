# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunnerCommands::Restore do
  it { is_expected.to be_a(PgEventstore::SubscriptionRunnerCommands::Base) }

  describe 'attributes' do
    it { is_expected.to have_attribute(:name).with_default_value('Restore') }
  end

  describe '.known_command?' do
    subject { described_class.known_command? }

    it { is_expected.to eq(true) }
  end

  describe '#exec_cmd' do
    subject { command.exec_cmd(subscription_runner) }

    let(:command) { described_class.new }
    let(:subscription_runner) { instance_spy(PgEventstore::SubscriptionRunner) }

    it 'restores SubscriptionRunner' do
      subject
      expect(subscription_runner).to have_received(:restore)
    end
  end
end
