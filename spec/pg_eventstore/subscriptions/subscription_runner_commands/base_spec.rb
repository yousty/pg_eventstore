# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunnerCommands::Base do
  it { is_expected.to be_a(PgEventstore::Extensions::OptionsExtension) }

  describe 'attributes' do
    it { is_expected.to have_attribute(:id) }
    it { is_expected.to have_attribute(:name).with_default_value('Base') }
    it { is_expected.to have_attribute(:subscription_id) }
    it { is_expected.to have_attribute(:subscriptions_set_id) }
    it { is_expected.to have_attribute(:data).with_default_value({}) }
    it { is_expected.to have_attribute(:created_at) }
  end

  describe '.known_command?' do
    subject { described_class.known_command? }

    it { is_expected.to eq(false) }
  end

  describe '.parse_data' do
    subject { described_class.parse_data(data) }

    let(:data) { { foo: :bar } }

    it { is_expected.to eq({}) }
  end

  describe '#==' do
    subject { instance == another_instance }

    let(:another_instance) { described_class.new(id: 1, name: 'Base', subscription_id: 1, subscriptions_set_id: 2) }
    let(:instance) { described_class.new(id: 1, name: 'Base', subscription_id: 1, subscriptions_set_id: 2) }

    context 'when all attributes match' do
      it { is_expected.to eq(true) }
    end

    context 'when some attribute differs' do
      let(:another_instance) do
        described_class.new(id: 1, name: 'Base', subscription_id: 1, subscriptions_set_id: 3)
      end

      it { is_expected.to eq(false) }
    end

    context 'when another instance is not a PgEventstore::SubscriptionRunnerCommands::Base object' do
      let(:another_instance) { Object.new }

      it { is_expected.to eq(false) }
    end
  end

  describe '#hash' do
    let(:hash) { {} }
    let(:cmd1) { described_class.new(id: 1, name: 'Base', subscription_id: 1, subscriptions_set_id: 2) }
    let(:cmd2) { described_class.new(id: 1, name: 'Base', subscription_id: 1, subscriptions_set_id: 2) }

    before do
      hash[cmd1] = :foo
    end

    context 'when commands match' do
      it 'recognizes second command' do
        expect(hash[cmd2]).to eq(:foo)
      end
    end

    context 'when commands does not match' do
      let(:cmd2) do
        described_class.new(id: 1, name: 'Base', subscription_id: 1, subscriptions_set_id: 2, data: { baz: :bar })
      end

      it 'does not recognize second command' do
        expect(hash[cmd2]).to eq(nil)
      end
    end
  end

  describe '#exec_cmd' do
    subject { command.exec_cmd(subscription_runner) }

    let(:command) { described_class.new }
    let(:subscription_runner) { instance_double(PgEventstore::SubscriptionRunner) }

    it { is_expected.to eq(nil) }
  end
end
