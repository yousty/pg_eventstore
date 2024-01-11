# frozen_string_literal: true

RSpec.describe PgEventstore::CommandHandlers::SubscriptionFeederCommands do
  let(:instance) { described_class.new(config_name, subscription_feeder) }
  let(:config_name) { :default }
  let(:subscription_feeder) { PgEventstore::SubscriptionFeeder.new(config_name, 'MySubscriptionsSet') }

  describe '#process' do
    subject { instance.process }

    let(:command_queries) { PgEventstore::SubscriptionsSetCommandQueries.new(PgEventstore.connection) }

    context 'when there are no commands' do
      it 'does nothing' do
        expect { subject }.not_to raise_error
      end
    end

    context 'when there is a "StopAll" command' do
      let!(:command) do
        command_queries.create_by(subscriptions_set_id: subscription_feeder.id, command_name: "StopAll")
      end

      before do
        allow(subscription_feeder).to receive(:stop_all).and_call_original
      end

      it 'stops all Subscriptions of the given SubscriptionFeeder' do
        subject
        expect(subscription_feeder).to have_received(:stop_all)
      end
      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscriptions_set_id: subscription_feeder.id, command_name: "StopAll")
        }.to(nil)
      end
    end

    context 'when there is a "StartAll" command' do
      let!(:command) do
        command_queries.create_by(subscriptions_set_id: subscription_feeder.id, command_name: "StartAll")
      end

      before do
        allow(subscription_feeder).to receive(:start_all).and_call_original
      end

      it 'starts all Subscriptions of the given SubscriptionFeeder' do
        subject
        expect(subscription_feeder).to have_received(:start_all)
      end
      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscriptions_set_id: subscription_feeder.id, command_name: "StartAll")
        }.to(nil)
      end
    end

    context 'when there is an unhandled command' do
      let!(:command) { command_queries.create_by(subscriptions_set_id: subscription_feeder.id, command_name: "FooCmd") }

      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscriptions_set_id: subscription_feeder.id, command_name: "FooCmd")
        }.to(nil)
      end

      context 'when PgEventstore logger is set' do
        before do
          PgEventstore.logger = Logger.new(STDOUT)
        end

        after do
          PgEventstore.logger = nil
        end

        it 'outputs warning' do
          expect { subject }.to(
            output(a_string_including(<<~TEXT)).to_stdout_from_any_process
              #{described_class.name}: Don't know how to handle #{command[:name].inspect}. Details: #{command.inspect}.
            TEXT
          )
        end
      end
    end

    context 'when non-existing config_name is given' do
      let(:config_name) { :non_existing_config }

      it 'raises error' do
        expect { subject }.to raise_error(/Could not find #{:non_existing_config.inspect} config/)
      end
    end
  end
end
