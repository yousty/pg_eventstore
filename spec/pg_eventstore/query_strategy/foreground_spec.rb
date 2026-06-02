# frozen_string_literal: true

RSpec.describe PgEventstore::QueryStrategy::Foreground do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#exec' do
    subject { instance.exec('select 1 as one') }

    it 'executes the query' do
      aggregate_failures do
        is_expected.to be_a(PG::Result)
        expect(subject.to_a).to eq([{ 'one' => 1 }])
      end
    end
  end

  describe '#exec_params' do
    subject { instance.exec_params('select 1 as one, $1::int as two', [2]) }

    it 'executes the query' do
      aggregate_failures do
        is_expected.to be_a(PG::Result)
        expect(subject.to_a).to eq([{ 'one' => 1, 'two' => 2 }])
      end
    end
  end
end
