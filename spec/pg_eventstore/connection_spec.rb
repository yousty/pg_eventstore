# frozen_string_literal: true

RSpec.describe PgEventstore::Connection do
  let(:instance) { described_class.new(uri: pg_uri, pool_size: 5, pool_timeout: 10) }
  let(:pg_uri) { PgEventstore.config.pg_uri }

  describe '#with' do
    it 'yields connection instance' do
      expect { |blk| instance.with(&blk) }.to yield_with_args(instance_of(PgEventstore::PgConnection))
    end

    describe 'behaviour after fork' do
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
    end
  end
end
