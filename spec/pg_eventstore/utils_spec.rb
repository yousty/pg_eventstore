# frozen_string_literal: true

RSpec.describe PgEventstore::Utils do
  describe '.underscore_str' do
    subject { described_class.underscore_str(str) }

    let(:str) { 'SomeName' }

    it { is_expected.to eq('some_name') }

    context 'when string is already underscored' do
      let(:str) { 'some_name' }

      it 'returns it as is' do
        is_expected.to eq('some_name')
      end
    end
  end

  describe '.benchmark' do
    subject { described_class.benchmark { sleep 1.1 } }

    it 'returns time the given block took to execute' do
      is_expected.to be_between(1.1, 1.2)
    end
  end
end
