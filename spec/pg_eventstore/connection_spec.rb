# frozen_string_literal: true

RSpec.describe PgEventstore::Connection do
  let(:instance) { described_class.new(uri: pg_uri, pool_size: 5, pool_timeout: 10) }
  let(:pg_uri) { PgEventstore.config.pg_uri }

  describe '#with' do
    it 'yields connection instance' do
      expect { |blk| instance.with(&blk) }.to yield_with_args(instance_of(PgEventstore::PgConnection))
    end

    describe 'behaviour after fork' do
      # rubocop:disable RSpec/MultipleExpectations
      it 'recovers itself' do
        results = ConnectionHelper.test_forking(instance)
        aggregate_failures do
          expect(results).to(
            all(satisfy { |attrs| attrs[:status] == 'OK' }),
            <<~TEXT
              Some processes have failed to execute queries(`nil' means the process was terminated abnormally):
              #{results.find { |attrs| attrs[:status] != 'OK' }&.dig(:status).inspect}
            TEXT
          )
          expect(results).to(
            all(satisfy { |attrs| attrs[:errors].to_s == '' }),
            <<~TEXT
              Looks like the same connection was reused by different process. Details:
              #{results.find { |attrs| attrs[:errors].to_s != '' }&.dig(:errors)}
            TEXT
          )
        end

        exception = nil
        begin
          instance.with { |c| c.exec('select version()') }
        rescue => exception
        end
        expect(exception).to be_nil, "Connection was not auto-recovered correctly: #{exception}"
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    describe 'retrying on errors' do
      subject do
        raised_count = 0
        instance.with do
          receiver.call
          if raised_count < times_to_raise
            raised_count += 1
            raise error
          end
        end
      end

      let(:error_class) { Class.new(StandardError) }
      let(:error) { error_class.new }
      let(:receiver) { spy('Receiver') }
      let(:times_to_raise) { 3 }

      before do
        allow(receiver).to receive(:call)
        # pre-allocate the connection
        instance.with { |c| c.exec('select 1') }
      end

      shared_examples 'does not recover from error' do
        it 'raises the error' do
          expect { subject }.to raise_error(error)
        end
        it 'retries only once' do
          begin
            subject
          rescue error_class
          end
          expect(receiver).to have_received(:call).twice
        end
        it 'throws the connection away' do
          expect {
            begin
              subject
            rescue error_class
            end
          }.to change { instance.instance_variable_get(:@pool).idle }.from(1).to(0)
        end
      end

      shared_examples 'recovers from error' do
        it 'does not raise error' do
          expect { subject }.not_to raise_error
        end
        it 're-executes successfully' do
          subject
          expect(receiver).to have_received(:call).twice
        end
        it 'does not throw away the connection from the pool' do
          expect {
            subject
          }.not_to change { instance.instance_variable_get(:@pool).idle }.from(1)
        end
      end

      context 'when error is StandardError' do
        it 'raises the error' do
          expect { subject }.to raise_error(error)
        end
        it 'does not retry' do
          begin
            subject
          rescue error_class
          end
          expect(receiver).to have_received(:call).once
        end
        it 'does not throw away the connection from the pool' do
          expect {
            begin
              subject
            rescue error_class
            end
          }.not_to change { instance.instance_variable_get(:@pool).idle }.from(1)
        end
      end

      context 'when error is PG::ConnectionBad' do
        let(:error_class) { PG::ConnectionBad }

        context 'when error is not fixed after one retry' do
          it_behaves_like 'does not recover from error'
        end

        context 'when error is fixed after one retry' do
          let(:times_to_raise) { 1 }

          it_behaves_like 'recovers from error'
        end
      end

      context 'when error is PG::UnableToSend' do
        let(:error_class) { PG::UnableToSend }

        context 'when error is not fixed after one retry' do
          it_behaves_like 'does not recover from error'
        end

        context 'when error is fixed after one retry' do
          let(:times_to_raise) { 1 }

          it_behaves_like 'recovers from error'
        end
      end
    end
  end
end
