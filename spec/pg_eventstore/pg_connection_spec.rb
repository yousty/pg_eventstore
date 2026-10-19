# frozen_string_literal: true

RSpec.describe PgEventstore::PgConnection do
  describe '#prepared_value' do
    subject do
      PgEventstore.connection.with do |conn|
        conn.prepared_value(value)
      end
    end

    let(:value) { nil }

    context 'when value is nil' do
      it 'converts it to NULL' do
        is_expected.to eq('NULL')
      end
    end

    context 'when value is a number' do
      let(:value) { 1 }

      it 'converts it to sql string literal' do
        is_expected.to eq("'1'")
      end
    end

    context 'when value is a string' do
      let(:value) { 'foo' }

      it 'converts it to sql string literal' do
        is_expected.to eq("'foo'")
      end
    end

    context 'when value is an array' do
      let(:value) { ['foo', 1] }

      it 'converts it to sql array literal' do
        is_expected.to eq("'{foo,1}'")
      end
    end

    context 'when value is a hash' do
      let(:value) { { foo: :bar } }

      it 'converts it to sql hash literal' do
        is_expected.to eq(%('{"foo":"bar"}'))
      end
    end

    context 'when value is true' do
      let(:value) { true }

      it 'converts it to sql string representation' do
        is_expected.to eq("'t'")
      end
    end

    context 'when value is false' do
      let(:value) { false }

      it 'converts it to sql string representation' do
        is_expected.to eq("'f'")
      end
    end
  end
end
