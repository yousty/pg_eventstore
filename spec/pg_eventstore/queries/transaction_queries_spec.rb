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

    describe 'transaction isolation level' do
      context 'when isolation level is not provided' do
        subject do
          instance.transaction do
            PgEventstore.connection.with do |c|
              c.exec('SHOW TRANSACTION ISOLATION LEVEL')
            end.to_a.dig(0, 'transaction_isolation')
          end
        end

        it 'it uses serializable isolation level' do
          is_expected.to eq('serializable')
        end
      end

      context 'when isolation level is provided' do
        subject do
          instance.transaction(isolation_level) do
            PgEventstore.connection.with do |c|
              c.exec('SHOW TRANSACTION ISOLATION LEVEL')
            end.to_a.dig(0, 'transaction_isolation')
          end
        end

        let(:isolation_level) { :read_committed }

        context 'when level is :read_committed' do
          it 'recognizes it' do
            is_expected.to eq('read committed')
          end
        end

        context 'when level is :repeatable_read' do
          let(:isolation_level) { :repeatable_read }

          it 'recognizes it' do
            is_expected.to eq('repeatable read')
          end
        end

        context 'when level is :serializable' do
          let(:isolation_level) { :serializable }

          it 'recognizes it' do
            is_expected.to eq('serializable')
          end
        end

        context 'when level is unhandled' do
          let(:isolation_level) { :some_value }

          it 'it falls back to serializable isolation level' do
            is_expected.to eq('serializable')
          end
        end
      end
    end
  end
end
