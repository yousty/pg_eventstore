# frozen_string_literal: true

RSpec.describe 'Logging PostgreSQL queries' do
  subject { PgEventstore.client.read(PgEventstore::Stream.all_stream) }

  context 'when PgEventstore.logger is not defined' do
    it 'does not log anything' do
      expect { subject }.not_to output.to_stdout_from_any_process
    end
  end

  context 'when PgEventstore.logger is defined' do
    let(:logger) { Logger.new($stdout) }

    before do
      PgEventstore.logger = logger
    end

    context 'when logger level is :debug' do
      before do
        logger.level = :debug
      end

      it 'outputs SQL query' do
        expect { subject }.to output(/SELECT events\.*/).to_stdout_from_any_process
      end
    end

    context 'when logger level is not :debug' do
      before do
        logger.level = :info
      end

      it 'does not log anything' do
        expect { subject }.not_to output.to_stdout_from_any_process
      end
    end
  end
end
