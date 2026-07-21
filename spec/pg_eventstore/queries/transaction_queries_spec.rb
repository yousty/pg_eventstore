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

        it 'uses serializable isolation level' do
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

          it 'falls back to serializable isolation level' do
            is_expected.to eq('serializable')
          end
        end
      end
    end

    context 'when transaction is started in read-only mode' do
      subject do
        instance.transaction(read_only: true) { command }
      end

      let(:command) do
        PgEventstore.client.read(PgEventstore::Stream.all_stream)
      end

      context 'when command does not modify database' do
        it 'executes it' do
          expect { subject }.not_to raise_error
        end
      end

      context 'when command modifies database' do
        let(:command) do
          stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
          PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
        end

        it 'raises error' do
          expect { subject }.to raise_error(PG::ReadOnlySqlTransaction)
        end
      end
    end

    describe 'error retries' do
      context 'when PG::UniqueViolation error raises' do
        context 'when error is not resolved during retries' do
          subject do
            instance.transaction do
              raise PG::UniqueViolation
            ensure
              retries_count.count += 1
            end
          end

          let(:retries_count) { Struct.new(:count).new(0) }

          it 'retries it up to MAX_NUMBER_OF_UNIQUE_CONSTRAINTS_ERROR_RETRIES times' do
            begin
              subject
            rescue PG::UniqueViolation
            end
            expect(retries_count.count).to eq(described_class::MAX_NUMBER_OF_UNIQUE_CONSTRAINTS_ERROR_RETRIES)
          end
          it 'raises error eventually' do
            expect { subject }.to raise_error(PG::UniqueViolation)
          end
        end

        context 'when error gets resolved during retries' do
          subject do
            errors_count = 0
            instance.transaction do
              errors_count += 1
              raise PG::TRSerializationFailure if errors_count < 3
            end
          end

          it 'does not raise an error' do
            expect { subject }.not_to raise_error
          end
        end
      end

      context 'when PG::TRSerializationFailure error raises' do
        subject do
          errors_count = 0
          instance.transaction do
            errors_count += 1
            raise PG::TRSerializationFailure if errors_count < 10
          end
        end

        it 'retries until error is resolved' do
          expect { subject }.not_to raise_error
        end
      end

      context 'when PG::TRDeadlockDetected error raises' do
        subject do
          errors_count = 0
          instance.transaction do
            errors_count += 1
            raise PG::TRDeadlockDetected if errors_count < 10
          end
        end

        it 'retries until error is resolved' do
          expect { subject }.not_to raise_error
        end
      end
    end
  end
end
