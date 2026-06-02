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

      let(:runner) { PgEventstore::AsyncQueryRunner.new }

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

      let(:runner) { PgEventstore::AsyncQueryRunner.new }

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
end
