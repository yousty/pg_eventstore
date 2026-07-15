# frozen_string_literal: true

RSpec.describe PgEventstore::QueryStrategy::Async do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#exec' do
    let(:query) { 'select 1 as one' }

    context 'when running without async runner' do
      subject { instance.exec(query) }

      it 'raises error' do
        expect { subject }.to raise_error(FiberError, 'attempt to yield on a not resumed fiber')
      end
    end

    context 'when running using async runner' do
      subject do
        instance = self.instance
        query = self.query
        result = nil
        runner.async { result = instance.exec(query) }
        runner.run
        result
      end

      let(:runner) { PgEventstore::AsyncRunner.new }

      context 'when query succeeds' do
        it 'returns result' do
          aggregate_failures do
            is_expected.to be_a(PG::Result)
            expect(subject.to_a).to eq([{ 'one' => 1 }])
          end
        end
      end

      context 'when query fails' do
        let(:query) { 'select foo as one' }

        it 'raises error' do
          expect { subject }.to raise_error(PG::UndefinedColumn, /column "foo" does not exist/)
        end
      end

      context 'when query returns multiple rows' do
        let(:query) { 'select id from generate_series(1, 1000) as t(id)' }

        it 'returns them all' do
          expect(subject.to_a).to eq(Array.new(1000) { { 'id' => _1 + 1 } })
        end
      end
    end
  end

  describe '#exec_params' do
    let(:query) { 'select 1 as one' }
    let(:args) { [] }

    context 'when running without async runner' do
      subject { instance.exec_params(query, args) }

      it 'raises error' do
        expect { subject }.to raise_error(FiberError, 'attempt to yield on a not resumed fiber')
      end
    end

    context 'when running using async runner' do
      subject do
        instance = self.instance
        query = self.query
        args = self.args
        result = nil
        runner.async { result = instance.exec_params(query, args) }
        runner.run
        result
      end

      let(:runner) { PgEventstore::AsyncRunner.new }

      context 'when query succeeds' do
        it 'returns result' do
          aggregate_failures do
            is_expected.to be_a(PG::Result)
            expect(subject.to_a).to eq([{ 'one' => 1 }])
          end
        end
      end

      context 'when query fails' do
        let(:query) { 'select foo as one' }

        it 'raises error' do
          expect { subject }.to raise_error(PG::UndefinedColumn, /column "foo" does not exist/)
        end
      end

      context 'when query returns multiple rows' do
        let(:query) { 'select id from generate_series(1, 1000) as t(id)' }

        it 'returns them all' do
          expect(subject.to_a).to eq(Array.new(1000) { { 'id' => _1 + 1 } })
        end
      end

      describe 'running query with parameters' do
        let(:query) do
          <<~SQL
            select global_position 
            from events_global_index 
            where stream_revision = $1 or global_position = any($2::bigint[])
            order by global_position asc
          SQL
        end
        let(:args) { [event1.stream_revision, [event2.global_position, event3.global_position]] }

        let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
        let(:event1) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
        let(:event2) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
        let(:event3) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }

        it 'handles them correctly' do
          expect(subject.to_a).to(
            eq(
              [
                { 'global_position' => event1.global_position },
                { 'global_position' => event2.global_position },
                { 'global_position' => event3.global_position },
              ]
            )
          )
        end
      end
    end
  end

  describe 'common cases' do
    it 'does not execute code after a canceled query' do
      continued = false
      strategy = instance
      query_runner = PgEventstore::AsyncRunner.new

      query_runner.async do
        begin
          strategy.exec('select pg_sleep(5)')
        rescue Exception
          # Even this must not intercept Fiber#kill.
        end

        continued = true
      end

      query_runner.async { strategy.exec('invalid sql') }
      aggregate_failures do
        expect { query_runner.run }.to raise_error(PG::SyntaxError)
        expect(continued).to be(false)
      end
    end

    it 'does not re-executes the original query when cancellation encounters a connection error' do
      PgEventstore.configure do |config|
        config.connection_pool_size = 2
      end
      strategy = instance
      query = 'select pg_sleep(5) /* 123 */'

      fiber = Fiber.new { strategy.exec(query) }
      fiber.resume

      terminated = Thread.new do
        PgEventstore.connection.with do |terminator|
          terminator.exec_params(<<~SQL, [query]).first['term']
            select pg_terminate_backend(pid) as term
            from pg_stat_activity
            where query = $1 and pid <> pg_backend_pid()
          SQL
        end
      end.value
      raise 'Failed to terminate the query backend' unless terminated

      fiber.raise(PgEventstore::AsyncRunner::Cancellation)

      expect(fiber).not_to be_alive
    ensure
      fiber.kill if fiber&.alive?
    end
  end
end
