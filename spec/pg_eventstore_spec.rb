# frozen_string_literal: true

RSpec.describe PgEventstore do
  describe '.configure' do
    it 'yields config' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(instance_of(described_class::Config))
    end

    context 'when config name is provided' do
      subject do
        described_class.configure(name: config_name) do |c|
          c.pg_uri = 'postgresql://localhost:5432'
        end
      end

      let(:config_name) { :some_config }

      before do
        described_class.configure(name: config_name) do |c|
          c.pg_uri = 'postgresql://localhost:5433'
        end
      end

      it 'yields config with correct name' do
        described_class.configure(name: config_name) do |c|
          expect(c.name).to eq(config_name)
        end
      end

      it 'does not change attributes of other configs' do
        expect { subject }.not_to change { described_class.config }
      end
      it 'changes attributes of the config with the given name' do
        expect { subject }.to change { described_class.config(config_name).options_hash }
      end
    end

    context "when user changes connection's options" do
      subject do
        described_class.configure do |c|
          c.pg_uri = 'postgresql://some.pg.host:5432/'
        end
      end

      it "changes the related connection's settings" do
        expect { subject }.to change {
          described_class.connection.instance_variable_get(:@uri)
        }.to('postgresql://some.pg.host:5432/')
      end
      it 're-setups a connection object' do
        expect { subject }.to change { described_class.connection.__id__ }
      end
    end

    describe 'multiple configuration calls' do
      subject do
        described_class.configure do |c|
          c.pg_uri = 'postgresql://some.pg.host:5432/'
        end
        described_class.configure do |c|
          c.max_count = 123
        end
      end

      before do
        described_class.configure do |c|
          c.pg_uri = 'postgresql://localhost:5432/'
        end
        described_class.configure do |c|
          c.max_count = 10
        end
      end

      it 'accumulates those changes' do
        expect { subject }.to change {
          described_class.config.options_hash
        }.from(a_hash_including(pg_uri: 'postgresql://localhost:5432/', max_count: 10)).
          to(a_hash_including(pg_uri: 'postgresql://some.pg.host:5432/', max_count: 123))
      end
    end

    it 'returns a frozen object' do
      expect(described_class.configure(&:itself)).to be_frozen
    end
  end

  describe '.config' do
    subject { described_class.config }

    it 'return :default config' do
      aggregate_failures do
        is_expected.to be_a(described_class::Config)
        expect(subject.name).to eq(:default)
      end
    end
    it 'memorizes the config object' do
      expect(subject.__id__).to eq(described_class.config.__id__)
    end

    context 'when config name of custom config is provided' do
      subject { described_class.config(:some_config) }

      before do
        described_class.configure(name: :some_config) do |c|
          c.pg_uri = 'postgresql://localhost:5432'
        end
      end

      it 'return the given config' do
        aggregate_failures do
          is_expected.to be_a(described_class::Config)
          expect(subject.name).to eq(:some_config)
        end
      end
      it 'memorizes the config object' do
        expect(subject.__id__).to eq(described_class.config(:some_config).__id__)
      end
    end

    context 'when config name of non existing config is provided' do
      subject { described_class.config(:some_config) }

      it 'raises error' do
        expect { subject }.to raise_error(RuntimeError, /Could not find :some_config config/)
      end
    end
  end

  describe '.connection' do
    subject { described_class.connection }

    before do
      described_class.configure do |c|
        c.pg_uri = 'postgresql://pg.host:5432'
        c.connection_pool_size = 21
        c.connection_pool_timeout = 43
      end
    end

    it 'returns the connection of default config' do
      aggregate_failures do
        is_expected.to be_a(described_class::Connection)
        expect(subject.instance_variable_get(:@uri)).to eq('postgresql://pg.host:5432')
        expect(subject.instance_variable_get(:@pool_size)).to eq(21)
        expect(subject.instance_variable_get(:@pool_timeout)).to eq(43)
      end
    end
    it 'memorizes the connection object' do
      expect(subject.__id__).to eq(described_class.connection.__id__)
    end

    context 'when config custom of existing config is provided' do
      subject { described_class.connection(:some_config) }

      before do
        described_class.configure(name: :some_config) do |c|
          c.pg_uri = 'postgresql://localhost:5432'
          c.connection_pool_size = 12
          c.connection_pool_timeout = 34
        end
      end

      it 'returns the connection of the given config' do
        aggregate_failures do
          is_expected.to be_a(described_class::Connection)
          expect(subject.instance_variable_get(:@uri)).to eq('postgresql://localhost:5432')
          expect(subject.instance_variable_get(:@pool_size)).to eq(12)
          expect(subject.instance_variable_get(:@pool_timeout)).to eq(34)
        end
      end
      it 'memorizes the config object' do
        expect(subject.__id__).to eq(described_class.connection(:some_config).__id__)
      end
    end

    context 'when config name of non existing config is provided' do
      subject { described_class.connection(:some_config) }

      it 'raises error' do
        expect { subject }.to raise_error(RuntimeError, /Could not find :some_config config/)
      end
    end
  end

  describe '.init_variables' do
    subject { described_class.send(:init_variables) }

    before do
      described_class.instance_variables.each { |var| described_class.instance_variable_set(var, nil) }
    end

    it 'assigns default config' do
      expect { subject }.to change {
        described_class.instance_variable_get(:@config)
      }.from(nil).to(hash_including(default: instance_of(PgEventstore::Config)))
    end
    it 'assigns mutex' do
      expect { subject }.to change {
        described_class.instance_variable_get(:@mutex)
      }.from(nil).to(instance_of(Thread::Mutex))
    end
    it 'inits connections hash' do
      expect { subject }.to change { described_class.instance_variable_get(:@connection) }.from(nil).to({})
    end
  end

  describe '.client' do
    context 'when no config name is given' do
      subject { described_class.client }

      it 'sets default config' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Client)
          expect(subject.send(:config).name).to eq(:default)
        end
      end
    end

    context 'when config name is given' do
      subject { described_class.client(config_name) }

      let(:config_name) { :some_config }

      before do
        described_class.configure(name: config_name, &:itself)
      end

      it 'sets the given config' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Client)
          expect(subject.send(:config).name).to eq(config_name)
        end
      end
    end

    context 'when non-existing config name is given' do
      subject { described_class.client(:non_existing_config) }

      it 'raises error' do
        expect { subject }.to raise_error(/Could not find #{:non_existing_config.inspect} config/)
      end
    end
  end

  describe '.maintenance' do
    context 'when no config name is given' do
      subject { described_class.maintenance }

      it 'sets default config' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Maintenance)
          expect(subject.send(:config).name).to eq(:default)
        end
      end
    end

    context 'when config name is given' do
      subject { described_class.maintenance(config_name) }

      let(:config_name) { :some_config }

      before do
        described_class.configure(name: config_name, &:itself)
      end

      it 'sets the given config' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::Maintenance)
          expect(subject.send(:config).name).to eq(config_name)
        end
      end
    end

    context 'when non-existing config name is given' do
      subject { described_class.maintenance(:non_existing_config) }

      it 'raises error' do
        expect { subject }.to raise_error(/Could not find #{:non_existing_config.inspect} config/)
      end
    end
  end

  describe '.subscriptions_manager' do
    context 'when no config name is given' do
      subject { described_class.subscriptions_manager(subscription_set: 'MySubscriptions') }

      it 'sets default config' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::SubscriptionsManager)
          expect(subject.send(:config).name).to eq(:default)
        end
      end
    end

    context 'when config name is given' do
      subject { described_class.subscriptions_manager(config_name, subscription_set: 'MySubscriptions') }

      let(:config_name) { :some_config }

      before do
        described_class.configure(name: config_name, &:itself)
      end

      it 'sets the given config' do
        aggregate_failures do
          is_expected.to be_a(PgEventstore::SubscriptionsManager)
          expect(subject.send(:config).name).to eq(config_name)
        end
      end
    end

    context 'when non-existing config name is given' do
      subject { described_class.subscriptions_manager(:non_existing_config, subscription_set: 'MySubscriptions') }

      it 'raises error' do
        expect { subject }.to raise_error(/Could not find #{:non_existing_config.inspect} config/)
      end
    end
  end
end
