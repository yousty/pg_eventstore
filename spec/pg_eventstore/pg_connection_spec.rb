# frozen_string_literal: true

RSpec.describe PgEventstore::PgConnection do
  describe '#compile' do
    subject do
      PgEventstore.connection.with do |conn|
        conn.compile(sql, params)
      end
    end

    describe 'positional parameters recognition' do
      let(:sql) do
        <<~SQL
          -- this is one: $1
          /* this is another one: $1 */
          select $1::int as a, $2 as b, $3::json as c, $4::int[] as d, '$5' as e, $$ $6 $$ as f,
            $body$ $1 $body$ as g, -- this is two: $2
            t."$1", t."$2", $5 as h, $6 as i, $7 j
          from (select 10 as "$1", 20 as "$2") as t
        SQL
      end
      let(:params) { [1, '2', { foo: :bar }, [1], true, false, nil] }

      it 'compiles into plain sql correctly' do
        exec_params_result = PgEventstore.connection.with do |conn|
          conn.exec_params(sql, params)
        end.to_a
        exec_compiled_result = PgEventstore.connection.with do |conn|
          conn.exec(subject)
        end.to_a
        aggregate_failures do
          is_expected.to include('-- this is one: $1')
          is_expected.to include('/* this is another one: $1 */')
          is_expected.to include('-- this is two: $2')
          # Ensure compiled sql provides the same result as exec_params(sql, params)
          expect(exec_params_result).to eq(exec_compiled_result)
        end
      end
    end

    describe 'escaping values after replacement' do
      let(:sql) { 'select $1 as one' }
      let(:params) { ["', '1"] }

      it 'escapes values correctly' do
        exec_compiled_result = PgEventstore.connection.with do |conn|
          conn.exec(subject)
        end.to_a
        expect(exec_compiled_result).to eq([{ 'one' => "', '1" }])
      end
    end
  end
end
