# frozen_string_literal: true

RSpec.describe PgEventstore::Extensions::UsingConnectionExtension do
  let(:dummy_class) do
    Class.new.tap do |klass|
      klass.include described_class
    end
  end

  describe '.connection' do
    subject { klass.connection }

    let(:klass) { dummy_class }

    context 'when .using_connection is not applied' do
      it 'raises error' do
        expect { subject }.to raise_error(/No connection was set/)
      end
    end

    context 'when .using_connection is applied' do
      let(:config_name) { :default }
      let(:klass) { dummy_class.using_connection(config_name) }

      it 'returns the connection' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Connection)
          is_expected.to eq(PgEventstore.connection(config_name))
        end
      end
      it 'does not override .connection of original class' do
        subject
        expect { dummy_class.connection }.to raise_error(/No connection was set/)
      end

      context 'when non-default config is given' do
        let(:config_name) { :some_config }

        before do
          PgEventstore.configure(name: config_name, &:itself)
        end

        after do
          PgEventstore.send(:init_variables)
        end

        it 'returns it' do
          aggregate_failures do
            is_expected.to be_a(PgEventstore::Connection)
            is_expected.to eq(PgEventstore.connection(config_name))
          end
        end
      end
    end
  end
end
