# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::Commands::BaseCommand do
  let(:instance) { described_class.new(options) }
  let(:options) { PgEventstore::CLI::ParserOptions::BaseOptions.new }

  describe '#call' do
    subject { instance.call }

    before do
      options.requires = ['non_existing_file.rb']
      allow(instance).to receive(:require)
    end

    it 'raises error' do
      expect { subject }.to raise_error(NotImplementedError)
    end
    it 'does not try to load the provided files list' do
      begin
        subject
      rescue NotImplementedError
      end
      expect(instance).not_to have_received(:require)
    end

    context 'when class gets inherited' do
      let(:child_class) do
        Class.new(described_class)
      end
      let(:instance) { child_class.new(options) }

      it 'raises error' do
        expect { subject }.to raise_error(NotImplementedError)
      end
      it 'loads the provided files list' do
        begin
          subject
        rescue NotImplementedError
        end
        expect(instance).to have_received(:require).with('non_existing_file.rb')
      end
    end
  end
end
