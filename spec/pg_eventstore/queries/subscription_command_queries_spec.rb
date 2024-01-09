# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionCommandQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }
  let(:subscription) { create_subscription }

  describe '#find_by' do
    subject { instance.find_by(subscription_id: subscription.id, command_name: command_name) }

    let(:command_name) { 'DoSomething' }

    context 'when command exists' do
      let!(:command) { instance.create_by(subscription_id: subscription.id, command_name: command_name) }

      it 'returns it ' do
        is_expected.to eq(command)
      end
    end

    context 'when command does not exist' do
      it { is_expected.to eq(nil) }
    end

    context 'when another command exists' do
      let!(:command) { instance.create_by(subscription_id: subscription.id, command_name: 'SomeAnotherCommand') }

      it { is_expected.to eq(nil) }
    end
  end

  describe '#create_by' do
    subject { instance.create_by(subscription_id: subscription.id, command_name: command_name) }

    let(:command_name) { 'DoSomething' }

    context 'when command exists' do
      let!(:command) { instance.create_by(subscription_id: subscription.id, command_name: command_name) }

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    context 'when command does not exist' do
      it 'creates it' do
        expect { subject }.to change {
          instance.find_by(subscription_id: subscription.id, command_name: command_name)
        }.to(a_hash_including(:id, :name, :subscription_id, :created_at))
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject[:id]).to be_a(Integer)
          expect(subject[:name]).to eq(command_name)
          expect(subject[:subscription_id]).to eq(subscription.id)
          expect(subject[:created_at]).to be_between(Time.now.utc - 1, Time.now.utc + 1)
        end
      end
    end

    context 'when command with the same name exist, but for different Subscription' do
      let(:another_subscription) { create_subscription(set: 'BarSet') }
      let!(:command) { instance.create_by(subscription_id: another_subscription.id, command_name: command_name) }

      it 'creates new command' do
        expect { subject }.to change {
          instance.find_by(subscription_id: subscription.id, command_name: command_name)
        }.to(a_hash_including(:id, :name, :subscription_id, :created_at))
      end
    end
  end

  describe '#find_commands' do
    subject { instance.find_commands(subscription_ids) }

    let(:subscription_ids) { [] }

    context 'when subscription ids is empty' do
      it { is_expected.to eq([]) }
    end

    context 'when subscription ids are present' do
      let(:subscription_ids) { [subscription.id, subscription3.id] }

      let(:subscription2) { create_subscription(set: 'Bar') }
      let(:subscription3) { create_subscription(set: 'Baz') }
      let!(:command1) { instance.create_by(subscription_id: subscription.id, command_name: 'Foo') }
      let!(:command2) { instance.create_by(subscription_id: subscription2.id, command_name: 'Foo') }
      let!(:command3) { instance.create_by(subscription_id: subscription3.id, command_name: 'Bar') }

      it 'returns existing commands by the given subscription ids' do
        is_expected.to eq([command1, command3])
      end
    end
  end

  describe '#delete' do
    subject { instance.delete(id) }

    let(:id) { -1 }

    context 'when command exists' do
      let(:id) { command[:id] }
      let!(:command) { instance.create_by(subscription_id: subscription.id, command_name: 'Foo') }

      it 'deletes it' do
        expect { subject }.to change { instance.find_by(subscription_id: subscription.id, command_name: 'Foo') }.to(nil)
      end
    end

    context 'when command does not exist' do
      it 'does not thing' do
        expect { subject }.not_to raise_error
      end
    end
  end
end
