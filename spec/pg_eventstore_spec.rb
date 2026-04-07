# frozen_string_literal: true

RSpec.describe PgEventstore do
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

  describe 'connection config' do
    subject do
      described_class.configure(name: config_name) do |c|
        c.pg_uri = 'postgres://localhost'
        c.connection_pool_size = 1
        c.connection_pool_timeout = 2
      end
    end

    let(:config_name) { :foo_cfg }

    before do
      described_class.configure(name: config_name) do |c|
        c.pg_uri = 'postgres://localhost:3000'
        c.connection_pool_size = 123
        c.connection_pool_timeout = 321
      end
    end

    it 'changes connection config' do
      connection_config = ->(conn) {
        conn.instance_eval { { uri: @uri, pool_size: @pool_size, pool_timeout: @pool_timeout } }
      }
      expect { subject }.to change {
        connection_config.(described_class.connection(config_name))
      }.to(uri: 'postgres://localhost', pool_size: 1, pool_timeout: 2)
    end
  end
end
