# frozen_string_literal: true

RSpec.describe PgEventstore::CLI do
  describe '.execute' do
    subject { described_class.execute(['--help']) }

    it 'executes the command by the given input' do
      expect { subject }.to output(a_string_including("Usage: pg-eventstore")).to_stdout
    end
  end
end
