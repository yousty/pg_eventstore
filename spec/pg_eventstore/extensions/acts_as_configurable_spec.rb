# frozen_string_literal: true

RSpec.describe PgEventstore::Extensions::ActsAsConfigurable do
  let(:dummy_module) do
    Module.new.tap do |m|
      m.extend described_class
    end
  end
  let(:config_class) do
    Class.new(PgEventstore::BasicConfig)
  end

  describe '.acts_as_configurable' do
    subject { dummy_module.acts_as_configurable(config_class:) }

    it 'defines DEFAULT_CONFIG constant' do
      expect { subject }.to change {
        begin
          dummy_module.const_get(:DEFAULT_CONFIG)
        rescue NameError
          nil
        end
      }.to(:default)
    end
    it 'defines CONFIG_CLASS constant' do
      expect { subject }.to change {
        begin
          dummy_module.const_get(:CONFIG_CLASS)
        rescue NameError
          nil
        end
      }.to(config_class)
    end
    it 'initializes @config instance variable' do
      expect { subject }.to change { dummy_module.instance_variable_get(:@config) }.to match(default: instance_of(config_class))
    end
    it 'extends the receiver with Configurable module' do
      expect { subject }.to change { dummy_module.is_a?(described_class::Configurable) }.to(true)
    end
  end

  describe 'Configurable methods' do
    before do
      dummy_module.acts_as_configurable(config_class:)
      config_class.option(:uri) { 'postgres://localhost:1111' }
      config_class.option(:max_count) { 1 }

      dummy_module.class_eval do
        def self.connection_options(config)
          { uri: config.uri, pool_size: 5, pool_timeout: 5 }
        end
      end
    end

    describe '.configure' do
      it 'yields config' do
        expect { |b| dummy_module.configure(&b) }.to yield_with_args(instance_of(config_class))
      end

      context 'when config name is provided' do
        subject do
          dummy_module.configure(name: config_name) do |c|
            c.uri = 'postgresql://localhost:5432'
          end
        end

        let(:config_name) { :some_config }

        before do
          dummy_module.configure(name: config_name) do |c|
            c.uri = 'postgresql://localhost:5433'
          end
        end

        it 'yields config with correct name' do
          dummy_module.configure(name: config_name) do |c|
            expect(c.name).to eq(config_name)
          end
        end

        it 'does not change attributes of other configs' do
          expect { subject }.not_to change { dummy_module.config }
        end
        it 'changes attributes of the config with the given name' do
          expect { subject }.to change { dummy_module.config(config_name).options_hash }
        end
      end

      context "when user changes connection's options" do
        subject do
          dummy_module.configure do |c|
            c.uri = 'postgresql://some.pg.host:5432/'
          end
        end

        it "changes the related connection's settings" do
          expect { subject }.to change {
            dummy_module.connection.instance_variable_get(:@uri)
          }.to('postgresql://some.pg.host:5432/')
        end
        it 're-setups a connection object' do
          expect { subject }.to change { dummy_module.connection.__id__ }
        end
      end

      describe 'multiple configuration calls' do
        subject do
          dummy_module.configure do |c|
            c.uri = 'postgresql://some.pg.host:5432/'
          end
          dummy_module.configure do |c|
            c.max_count = 123
          end
        end

        before do
          dummy_module.configure do |c|
            c.uri = 'postgresql://localhost:5432/'
          end
          dummy_module.configure do |c|
            c.max_count = 10
          end
        end

        it 'accumulates those changes' do
          expect { subject }.to change {
            dummy_module.config.options_hash
          }.from(a_hash_including(uri: 'postgresql://localhost:5432/', max_count: 10)).
            to(a_hash_including(uri: 'postgresql://some.pg.host:5432/', max_count: 123))
        end
      end

      it 'returns a frozen object' do
        expect(dummy_module.configure(&:itself)).to be_frozen
      end
    end

    describe '.config' do
      subject { dummy_module.config }

      it 'return :default config' do
        aggregate_failures do
          is_expected.to be_a(config_class)
          expect(subject.name).to eq(:default)
        end
      end
      it 'memorizes the config object' do
        expect(subject.__id__).to eq(dummy_module.config.__id__)
      end

      context 'when config name of custom config is provided' do
        subject { dummy_module.config(:some_config) }

        before do
          dummy_module.configure(name: :some_config) do |c|
            c.uri = 'postgresql://localhost:5432'
          end
        end

        it 'return the given config' do
          aggregate_failures do
            is_expected.to be_a(config_class)
            expect(subject.name).to eq(:some_config)
          end
        end
        it 'memorizes the config object' do
          expect(subject.__id__).to eq(dummy_module.config(:some_config).__id__)
        end
      end

      context 'when config name of non existing config is provided' do
        subject { dummy_module.config(:some_config) }

        it 'raises error' do
          expect { subject }.to raise_error(RuntimeError, /Could not find :some_config config/)
        end
      end
    end

    describe '.connection' do
      subject { dummy_module.connection }

      before do
        dummy_module.configure do |c|
          c.uri = 'postgresql://pg.host:5432'
        end
      end

      it 'returns the connection of default config' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Connection)
          expect(subject.instance_variable_get(:@uri)).to eq('postgresql://pg.host:5432')
        end
      end
      it 'memorizes the connection object' do
        expect(subject.__id__).to eq(dummy_module.connection.__id__)
      end

      context 'when config custom of existing config is provided' do
        subject { dummy_module.connection(:some_config) }

        before do
          dummy_module.configure(name: :some_config) do |c|
            c.uri = 'postgresql://localhost:5432'
          end
        end

        it 'returns the connection of the given config' do
          aggregate_failures do
            is_expected.to be_a(PgEventstore::Connection)
            expect(subject.instance_variable_get(:@uri)).to eq('postgresql://localhost:5432')
          end
        end
        it 'memorizes the config object' do
          expect(subject.__id__).to eq(dummy_module.connection(:some_config).__id__)
        end
      end

      context 'when config name of non existing config is provided' do
        subject { dummy_module.connection(:some_config) }

        it 'raises error' do
          expect { subject }.to raise_error(RuntimeError, /Could not find :some_config config/)
        end
      end
    end

    describe '.init_variables' do
      subject { dummy_module.send(:init_variables) }

      before do
        dummy_module.instance_variables.each { |var| dummy_module.instance_variable_set(var, nil) }
      end

      it 'assigns default config' do
        expect { subject }.to change {
          dummy_module.instance_variable_get(:@config)
        }.from(nil).to(hash_including(default: instance_of(config_class)))
      end
      it 'assigns mutex' do
        expect { subject }.to change {
          dummy_module.instance_variable_get(:@mutex)
        }.from(nil).to(instance_of(Thread::Mutex))
      end
      it 'inits connections hash' do
        expect { subject }.to change { dummy_module.instance_variable_get(:@connection) }.from(nil).to({})
      end
    end
  end
end
