# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionCommandQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }
  let(:subscription) { SubscriptionsHelper.create }
  let(:subscriptions_set) { SubscriptionsSetHelper.create }

  describe '#find_by' do
    subject do
      instance.find_by(
        subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: command_name
      )
    end

    let(:command_name) { 'DoSomething' }

    context 'when command exists' do
      let!(:command) do
        instance.create(
          subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: command_name,
          data: {}
        )
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
        instance.create(
          subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id,
          command_name: 'SomeAnotherCommand', data: {}
        )
      end

      it { is_expected.to eq(nil) }
    end

    context 'when same command exists, but for different SubscriptionsSet' do
      let!(:command) do
        instance.create(
          subscription_id: subscription.id, subscriptions_set_id: another_subscriptions_set.id,
          command_name: command_name, data: {}
        )
      end
      let(:another_subscriptions_set) { SubscriptionsSetHelper.create(name: 'BarSet') }

      it { is_expected.to eq(nil) }
    end
  end

  describe '#create' do
    subject do
      instance.create(
        subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: command_name,
        data: { foo: :bar }
      )
    end

    let(:command_name) { 'DoSomething' }

    shared_examples 'creates a command' do
      it 'creates new command' do
        expect { subject }.to change {
          instance.find_by(
            subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: command_name
          )
        }.to(instance_of(PgEventstore::SubscriptionRunnerCommands::Base))
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject.id).to be_a(Integer)
          expect(subject.name).to eq(command_name)
          expect(subject.subscription_id).to eq(subscription.id)
          expect(subject.data).to eq('foo' => 'bar')
          expect(subject.created_at).to be_between(Time.now.utc - 1, Time.now.utc + 1)
        end
      end
    end

    context 'when command exists' do
      let!(:command) do
        instance.create(
          subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: command_name,
          data: {}
        )
      end

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    context 'when command for the same subscription, but for the another subscriptions set exists' do
      let!(:command) do
        instance.create(
          subscription_id: subscription.id, subscriptions_set_id: subscriptions_set2.id, command_name: command_name,
          data: {}
        )
      end
      let(:subscriptions_set2) { SubscriptionsSetHelper.create(name: 'BarSet') }

      it_behaves_like 'creates a command'
    end

    context 'when command does not exist' do
      it_behaves_like 'creates a command'
    end

    context 'when command with the same name exist, but for different Subscription' do
      let(:another_subscription) { SubscriptionsHelper.create(set: 'BarSet') }
      let!(:command) do
        instance.create(
          subscription_id: another_subscription.id, subscriptions_set_id: subscriptions_set.id,
          command_name: command_name, data: {}
        )
      end

      it_behaves_like 'creates a command'
    end
  end

  describe '#find_commands' do
    subject { instance.find_commands(subscription_ids, subscriptions_set_id: subscriptions_set.id) }

    let(:subscription_ids) { [] }

    context 'when subscription ids is empty' do
      it { is_expected.to eq([]) }
    end

    context 'when subscription ids are present' do
      let(:subscription_ids) { [subscription.id, subscription3.id] }

      let(:another_subscriptions_set) { SubscriptionsSetHelper.create(name: 'BarSet') }
      let(:subscription2) { SubscriptionsHelper.create(set: 'Bar') }
      let(:subscription3) { SubscriptionsHelper.create(set: 'Baz') }
      let!(:command1) do
        instance.create(
          subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: 'Foo', data: {}
        )
      end
      let!(:command2) do
        instance.create(
          subscription_id: subscription2.id, subscriptions_set_id: subscriptions_set.id, command_name: 'Foo', data: {}
        )
      end
      let!(:command3) do
        instance.create(
          subscription_id: subscription3.id, subscriptions_set_id: subscriptions_set.id, command_name: 'Bar', data: {}
        )
      end
      let!(:command4) do
        instance.create(
          subscription_id: subscription3.id, subscriptions_set_id: another_subscriptions_set.id, command_name: 'Bar',
          data: {}
        )
      end

      it 'returns existing commands by the given subscription ids' do
        is_expected.to eq([command1, command3])
      end
    end
  end

  describe '#delete' do
    subject { instance.delete(id) }

    let(:id) { -1 }

    context 'when command exists' do
      let(:id) { command.id }
      let!(:command) do
        instance.create(
          subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: 'Foo', data: {}
        )
      end

      it 'deletes it' do
        expect { subject }.to change {
          instance.find_by(
            subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: 'Foo'
          )
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
        subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: command_name,
        data: { 'foo' => 'bar' }
      )
    end

    let(:command_name) { 'FooCmd' }

    describe 'when command does not exists' do
      it 'creates it' do
        expect { subject }.to change {
          instance.find_by(
            subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: command_name
          )
        }.to(instance_of(PgEventstore::SubscriptionRunnerCommands::Base))
      end
      it 'has proper attributes' do
        aggregate_failures do
          expect(subject.subscription_id).to eq(subscription.id)
          expect(subject.subscriptions_set_id).to eq(subscriptions_set.id)
          expect(subject.name).to eq(command_name)
          expect(subject.data).to eq('foo' => 'bar')
        end
      end
    end

    describe 'when command already exists' do
      let!(:command) do
        instance.create(
          subscription_id: subscription.id, subscriptions_set_id: subscriptions_set.id, command_name: command_name,
          data: {}
        )
      end

      it 'returns it' do
        is_expected.to eq(command)
      end
      it 'does not create another command' do
        expect { subject }.not_to change {
          PgEventstore.connection.with { |c| c.exec('select count(*) from subscription_commands').to_a.first }
        }
      end
    end
  end
end
