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
end
