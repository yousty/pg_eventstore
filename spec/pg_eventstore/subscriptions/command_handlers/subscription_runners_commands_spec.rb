# frozen_string_literal: true

RSpec.describe PgEventstore::CommandHandlers::SubscriptionRunnersCommands do
  let(:instance) { described_class.new(config_name, runners) }
  let(:config_name) { :default }
  let(:runners) { [runner1, runner2] }
  let(:runner1) do
    PgEventstore::SubscriptionRunner.new(
      stats: PgEventstore::SubscriptionHandlerPerformance.new,
      events_processor: PgEventstore::EventsProcessor.new(proc { }),
      subscription: SubscriptionsHelper.create_with_connection(name: 'Subscr1')
    )
  end
  let(:runner2) do
    PgEventstore::SubscriptionRunner.new(
      stats: PgEventstore::SubscriptionHandlerPerformance.new,
      events_processor: PgEventstore::EventsProcessor.new(proc { }),
      subscription: SubscriptionsHelper.create_with_connection(name: 'Subscr2')
    )
  end

  describe '#process' do
    subject { instance.process }

    let(:command_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    after do
      runners.each(&:stop_async).each(&:wait_for_finish)
    end

    shared_examples 'executes the command' do
      before do
        runners.each do |runner|
          allow(runner).to receive(command_method).and_call_original
        end
      end

      shared_examples 'command from another collection' do
        let!(:another_command) do
          command_queries.create_by(
            subscription_id: SubscriptionsHelper.create(name: 'Subscr3').id, command_name: command_name
          )
        end

        it 'does not delete it' do
          expect { subject }.not_to(
            change {
              command_queries.find_by(
                subscription_id: another_command[:subscription_id], command_name: another_command[:name]
              )
            }
          )
        end
      end

      context 'when command exists only for the second runner' do
        let!(:command) { command_queries.create_by(subscription_id: runner2.id, command_name: command_name) }

        it 'performs the command only for it' do
          subject
          aggregate_failures do
            expect(runner1).not_to have_received(command_method)
            expect(runner2).to have_received(command_method).once
          end
        end
        it 'deletes the command' do
          expect { subject }.to change {
            command_queries.find_by(subscription_id: runner2.id, command_name: command_name)
          }.to(nil)
        end
        it_behaves_like 'command from another collection'
      end

      context 'when commands exist for both runners' do
        let!(:command1) { command_queries.create_by(subscription_id: runner1.id, command_name: command_name) }
        let!(:command2) { command_queries.create_by(subscription_id: runner2.id, command_name: command_name) }

        it 'performs the command for both of them' do
          subject
          aggregate_failures do
            expect(runner1).to have_received(command_method).once
            expect(runner2).to have_received(command_method).once
          end
        end
        it 'deletes the command of first runner' do
          expect { subject }.to change {
            command_queries.find_by(subscription_id: runner1.id, command_name: command_name)
          }.to(nil)
        end
        it 'deletes the command of second runner' do
          expect { subject }.to change {
            command_queries.find_by(subscription_id: runner2.id, command_name: command_name)
          }.to(nil)
        end
        it_behaves_like 'command from another collection'
      end
    end

    context 'when "Stop" command is given' do
      let(:command_name) { 'Stop' }

      it_behaves_like 'executes the command' do
        let(:command_method) { :stop_async }
      end
    end

    context 'when "Restore" command is given' do
      let(:command_name) { 'Restore' }

      it_behaves_like 'executes the command' do
        let(:command_method) { :restore }
      end
    end

    context 'when "Start" command is given' do
      let(:command_name) { 'Start' }

      it_behaves_like 'executes the command' do
        let(:command_method) { :start }
      end
    end

    context 'when an unhandled command is given' do
      let!(:command) { command_queries.create_by(subscription_id: runner1.id, command_name: "FooCmd") }

      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscription_id: runner1.id, command_name: "FooCmd")
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
