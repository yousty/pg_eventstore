# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsSetCommandQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }
  let(:subscriptions_set) { create_subscriptions_set }

  describe '#find_by' do
    subject { instance.find_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name) }

    let(:command_name) { 'DoSomething' }

    context 'when command exists' do
      let!(:command) { instance.create_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name) }

      it 'returns it ' do
        is_expected.to eq(command)
      end
    end

    context 'when command does not exist' do
      it { is_expected.to eq(nil) }
    end

    context 'when another command exists' do
      let!(:command) do
        instance.create_by(subscriptions_set_id: subscriptions_set.id, command_name: 'SomeAnotherCommand')
      end

      it { is_expected.to eq(nil) }
    end
  end

  describe '#create_by' do
    subject { instance.create_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name) }

    let(:command_name) { 'DoSomething' }

    context 'when command exists' do
      let!(:command) { instance.create_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name) }

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    context 'when command does not exist' do
      it 'creates it' do
        expect { subject }.to change {
          instance.find_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name)
        }.to(a_hash_including(:id, :name, :subscriptions_set_id, :created_at))
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject[:id]).to be_a(Integer)
          expect(subject[:name]).to eq(command_name)
          expect(subject[:subscriptions_set_id]).to eq(subscriptions_set.id)
          expect(subject[:created_at]).to be_between(Time.now.utc - 1, Time.now.utc + 1)
        end
      end
    end

    context 'when command with the same name exist, but for different SubscriptionsSet' do
      let(:another_subscriptions_set) { create_subscriptions_set(name: 'BarSet') }
      let!(:command) do
        instance.create_by(subscriptions_set_id: another_subscriptions_set.id, command_name: command_name)
      end

      it 'creates new command' do
        expect { subject }.to change {
          instance.find_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name)
        }.to(a_hash_including(:id, :name, :subscriptions_set_id, :created_at))
      end
    end
  end

  describe '#find_commands' do
    subject { instance.find_commands(subscriptions_set_id) }

    let(:subscriptions_set_id) { subscriptions_set.id }

    let(:another_subscriptions_set) { create_subscriptions_set(name: 'BarSet') }
    let!(:command1) { instance.create_by(subscriptions_set_id: subscriptions_set.id, command_name: 'Foo') }
    let!(:command2) { instance.create_by(subscriptions_set_id: another_subscriptions_set.id, command_name: 'Foo') }
    let!(:command3) { instance.create_by(subscriptions_set_id: subscriptions_set.id, command_name: 'Bar') }

    it 'returns existing commands by the given SubscriptionsSet ids' do
      is_expected.to eq([command1, command3])
    end
  end

  describe '#delete' do
    subject { instance.delete(id) }

    let(:id) { -1 }

    context 'when command exists' do
      let(:id) { command[:id] }
      let!(:command) { instance.create_by(subscriptions_set_id: subscriptions_set.id, command_name: 'Foo') }

      it 'deletes it' do
        expect { subject }.to change {
          instance.find_by(subscriptions_set_id: subscriptions_set.id, command_name: 'Foo')
        }.to(nil)
      end
    end

    context 'when command does not exist' do
      it 'does not thing' do
        expect { subject }.not_to raise_error
      end
    end
  end
end
