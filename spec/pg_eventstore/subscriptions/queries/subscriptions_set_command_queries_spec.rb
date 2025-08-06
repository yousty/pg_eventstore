# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsSetCommandQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }
  let(:subscriptions_set) { SubscriptionsSetHelper.create }

  describe '#find_by' do
    subject { instance.find_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name) }

    let(:command_name) { 'DoSomething' }

    context 'when command exists' do
      let!(:command) do
        instance.create(subscriptions_set_id: subscriptions_set.id, command_name: command_name, data: {})
      end

      it 'returns it' do
        is_expected.to eq(command)
      end
    end

    context 'when command does not exist' do
      it { is_expected.to eq(nil) }
    end

    context 'when another command exists' do
      let!(:command) do
        instance.create(subscriptions_set_id: subscriptions_set.id, command_name: 'SomeAnotherCommand', data: {})
      end

      it { is_expected.to eq(nil) }
    end
  end

  describe '#create' do
    subject do
      instance.create(subscriptions_set_id: subscriptions_set.id, command_name: command_name, data: { 'foo' => 'bar' })
    end

    let(:command_name) { 'DoSomething' }

    context 'when command exists' do
      let!(:command) do
        instance.create(subscriptions_set_id: subscriptions_set.id, command_name: command_name, data: {})
      end

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    context 'when command does not exist' do
      it 'creates it' do
        expect { subject }.to change {
          instance.find_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name)
        }.to(instance_of(PgEventstore::SubscriptionFeederCommands::Base))
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject.id).to be_a(Integer)
          expect(subject.name).to eq(command_name)
          expect(subject.subscriptions_set_id).to eq(subscriptions_set.id)
          expect(subject.created_at).to be_between(Time.now.utc - 1, Time.now.utc + 1)
          expect(subject.data).to eq('foo' => 'bar')
        end
      end
    end

    context 'when command with the same name exist, but for different SubscriptionsSet' do
      let(:another_subscriptions_set) { SubscriptionsSetHelper.create(name: 'BarSet') }
      let!(:command) do
        instance.create(subscriptions_set_id: another_subscriptions_set.id, command_name: command_name, data: {})
      end

      it 'creates new command' do
        expect { subject }.to change {
          instance.find_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name)
        }.to(instance_of(PgEventstore::SubscriptionFeederCommands::Base))
      end
    end
  end

  describe '#find_commands' do
    subject { instance.find_commands(subscriptions_set_id) }

    let(:subscriptions_set_id) { subscriptions_set.id }

    let(:another_subscriptions_set) { SubscriptionsSetHelper.create(name: 'BarSet') }
    let!(:command1) { instance.create(subscriptions_set_id: subscriptions_set.id, command_name: 'Foo', data: {}) }
    let!(:command2) do
      instance.create(subscriptions_set_id: another_subscriptions_set.id, command_name: 'Foo', data: {})
    end
    let!(:command3) { instance.create(subscriptions_set_id: subscriptions_set.id, command_name: 'Bar', data: {}) }

    it 'returns existing commands by the given SubscriptionsSet ids' do
      is_expected.to eq([command1, command3])
    end
  end

  describe '#delete' do
    subject { instance.delete(id) }

    let(:id) { -1 }

    context 'when command exists' do
      let(:id) { command.id }
      let!(:command) { instance.create(subscriptions_set_id: subscriptions_set.id, command_name: 'Foo', data: {}) }

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

  describe '#find_or_create_by' do
    subject do
      instance.find_or_create_by(
        subscriptions_set_id: subscriptions_set.id, command_name: command_name, data: { 'foo' => 'bar' }
      )
    end

    let(:command_name) { 'FooCmd' }

    describe 'when command does not exists' do
      it 'creates it' do
        expect { subject }.to change {
          instance.find_by(subscriptions_set_id: subscriptions_set.id, command_name: command_name)
        }.to(instance_of(PgEventstore::SubscriptionFeederCommands::Base))
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject.id).to be_a(Integer)
          expect(subject.name).to eq(command_name)
          expect(subject.subscriptions_set_id).to eq(subscriptions_set.id)
          expect(subject.data).to eq('foo' => 'bar')
        end
      end
    end

    describe 'when command already exists' do
      let!(:command) do
        instance.create(subscriptions_set_id: subscriptions_set.id, command_name: command_name, data: {})
      end

      it 'returns it' do
        is_expected.to eq(command)
      end
      it 'does not create another command' do
        expect { subject }.not_to change {
          PgEventstore.connection.with { |c| c.exec('select count(*) from subscriptions_set_commands').to_a.first }
        }
      end
    end
  end
end
