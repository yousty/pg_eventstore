# frozen_string_literal: true

RSpec.describe PgEventstore::Config do
  subject { instance }

  let(:instance) { described_class.new(name: :my_awesome_config) }

  it { is_expected.to be_a(PgEventstore::Extensions::OptionsExtension) }
  it { expect(subject.name).to eq(:my_awesome_config) }

  describe 'attributes' do
    it do
      is_expected.to have_option(:pg_uri).with_default_value('postgresql://postgres:postgres@localhost:5432/eventstore')
    end
    it { is_expected.to have_option(:max_count).with_default_value(1000) }
    it { is_expected.to have_option(:middlewares).with_default_value({}) }
    it do
      is_expected.to(
        have_option(:event_class_resolver).with_default_value(instance_of(PgEventstore::EventClassResolver))
      )
    end
    it { is_expected.to have_option(:connection_pool_size).with_default_value(5) }
    it { is_expected.to have_option(:connection_pool_timeout).with_default_value(5) }
    it { is_expected.to have_option(:subscription_pull_interval).with_default_value(2) }
    it { is_expected.to have_option(:subscription_max_retries).with_default_value(100) }
    it { is_expected.to have_option(:subscription_restart_terminator) }
  end

  describe '#connection_options' do
    subject { instance.connection_options }

    before do
      instance.pg_uri = 'postgresql://localhost:5432'
      instance.connection_pool_size = 12
      instance.connection_pool_timeout = 34
    end

    it { is_expected.to eq(uri: 'postgresql://localhost:5432', pool_size: 12, pool_timeout: 34) }
  end
end
