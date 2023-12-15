# frozen_string_literal: true

RSpec.describe PgEventstore::TransactionQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#transaction' do
    it 'yields the given block' do
      expect { |blk| instance.transaction(&blk) }.to yield_with_no_args
    end

    context 'when transaction is not started yet' do
      it 'starts it' do
        expect(instance.transaction { PgEventstore.connection.with(&:transaction_status) }).to eq(PG::PQTRANS_INTRANS)
      end
    end

    context 'when another transaction is already started' do
      it 'does not start another one' do
        expect do
          instance.transaction do
            instance.transaction do
              PgEventstore.connection.with { |c| c.exec('select version()') }
            end
          end
        end.not_to output.to_stderr_from_any_process
      end
    end
  end
end
