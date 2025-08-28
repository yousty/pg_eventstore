# frozen_string_literal: true

RSpec.describe PgEventstore::CLI do
  describe '.execute' do
    subject { described_class.execute(%w[subscriptions stop]) }

    before do
      PgEventstore.logger = Logger.new($stdout)
    end

    it 'executes the command by the given input' do
      expected_message = a_string_including('Pid file "/tmp/pg-es_subscriptions.pid" does not exist or empty.')
      aggregate_failures do
        expect { subject }.to output(expected_message).to_stdout_from_any_process
        is_expected.to eq(described_class::ExitCodes::ERROR)
      end
    end
  end
end
