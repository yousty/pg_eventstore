# frozen_string_literal: true

RSpec.describe PgEventstore::RunnerRecoveryStrategies::RestoreConnection do
  let(:instance) { described_class.new(:default) }

  it { expect(instance).to be_a(PgEventstore::RunnerRecoveryStrategy) }

  describe '#recovers?' do
    subject { instance.recovers?(error) }

    let(:error) { StandardError.new }

    context 'when error is a PG::ConnectionBad' do
      let(:error) { PG::ConnectionBad.new }

      it { is_expected.to eq(true) }
    end

    context 'when error is a PG::UnableToSend' do
      let(:error) { PG::UnableToSend.new }

      it { is_expected.to eq(true) }
    end

    context 'when error is a ConnectionPool::TimeoutError' do
      let(:error) { ConnectionPool::TimeoutError.new }

      it { is_expected.to eq(true) }
    end

    context 'when error is something else' do
      it { is_expected.to eq(false) }
    end
  end

  describe '#recover' do
    subject { instance.recover(error) }

    let(:error) { StandardError.new }

    before do
      stub_const("#{described_class}::TIME_BETWEEN_RETRIES", 1)
      PgEventstore.configure do |c|
        c.pg_uri = 'postgresql://localhost:1234/eventstore'
      end
    end

    around do |ex|
      # Simulate the restoration process by resetting the config asynchronous
      restore_job = Thread.new do
        sleep 2
        ConfigHelper.reconfigure
      end
      ex.run
      restore_job.exit
    end

    it 'waits until connection gets restored' do
      seconds = PgEventstore::Utils.benchmark { subject }
      aggregate_failures do
        expect(seconds).to be_between(2.0, 2.1)
        expect(subject).to eq(true)
      end
    end
  end
end
