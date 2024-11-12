# frozen_string_literal: true

RSpec.describe 'CLI integration' do
  describe 'starting subscription' do
    subject { subscriptions_pid }

    let(:subscriptions_pid) do
      args = [
        'bundle', 'exec', 'exe/pg-eventstore', 'subscriptions', 'start',
        '-r', './spec/support/cli_helper.rb',
        '-r', CLIHelper.running_subscriptions_file_path
      ]
      Process.spawn({ 'PG_EVENTSTORE_URI' => PgEventstore.config.pg_uri }, *args).tap do
        Process.detach(_1)
      end
    end

    let(:stream) { PgEventstore::Stream.new(context: 'Foo', stream_name: 'FooStream', stream_id: '1') }
    let!(:event) do
      PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo', data: { foo: 'bar' }))
    end

    before do
      CLIHelper.persist_running_subscriptions_file
    end

    after do
      Process.kill('TERM', subscriptions_pid)
      begin
        Process.wait(subscriptions_pid)
      rescue Errno::ECHILD
      end
    end

    it 'processes events' do
      expect {
        subject
        # Let subscriptions to process event
        sleep 3
      }.to change {
        CLIHelper.processed_events
      }.to(
        array_including(
          a_hash_including(type: 'Foo', data: { foo: 'bar' })
        )
      )
    end
    it 'persists pid into a file' do
      expect {
        subject
        # Let subscriptions to process event
        sleep 3
      }.to change {
        PgEventstore::Utils.read_pid('/tmp/pg-es_subscriptions.pid')&.to_i
      }.to(subscriptions_pid)
    end
  end

  describe 'persisting pid into provided pid path' do
    subject { subscriptions_pid }

    let(:subscriptions_pid) do
      args = [
        'bundle', 'exec', 'exe/pg-eventstore', 'subscriptions', 'start',
        '-r', './spec/support/cli_helper.rb',
        '-r', CLIHelper.running_subscriptions_file_path,
        '-p', pid_file_path
      ]
      Process.spawn({ 'PG_EVENTSTORE_URI' => PgEventstore.config.pg_uri }, *args).tap do
        Process.detach(_1)
      end
    end

    let(:pid_file_path) { "/tmp/my_pid_file_#{SecureRandom.hex(8)}.pid" }

    before do
      CLIHelper.persist_running_subscriptions_file
    end

    after do
      Process.kill('TERM', subscriptions_pid)
      begin
        Process.wait(subscriptions_pid)
      rescue Errno::ECHILD
      end
    end

    it 'persists pid into the given file' do
      expect {
        subject
        # Let subscriptions process to start
        sleep 3
      }.to change {
        PgEventstore::Utils.read_pid(pid_file_path)&.to_i
      }.to(subscriptions_pid)
    end
  end

  describe 'starting stuck subscriptions' do
    subject { subscriptions_pid }

    let(:subscriptions_pid) do
      args = [
        'bundle', 'exec', 'exe/pg-eventstore', 'subscriptions', 'start',
        '-r', CLIHelper.stub_consts_file_path,
        '-r', './spec/support/cli_helper.rb',
        '-r', CLIHelper.running_subscriptions_file_path
      ]
      Process.spawn({ 'PG_EVENTSTORE_URI' => PgEventstore.config.pg_uri, 'RUBYOPT' => 'W0' }, *args).tap do
        Process.detach(_1)
      end
    end

    let(:stream) { PgEventstore::Stream.new(context: 'Foo', stream_name: 'FooStream', stream_id: '1') }
    let!(:event) do
      PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo', data: { foo: 'bar' }))
    end

    let(:subscriptions_set) do
      SubscriptionsSetHelper.create(name: 'MyAwesomeSubscriptions')
    end
    let!(:existing_locked_subscription) do
      SubscriptionsHelper.create_with_connection(
        name: 'Foo events Subscription', set: subscriptions_set.name, locked_by: subscriptions_set.id
      )
    end

    before do
      CLIHelper.persist_running_subscriptions_file
      CLIHelper.persist_stub_consts_file
    end

    after do
      Process.kill('TERM', subscriptions_pid)
      begin
        Process.wait(subscriptions_pid)
      rescue Errno::ECHILD
      end
    end

    it 'processes events' do
      expect {
        subject
        # Let subscriptions to unlock and start
        sleep 3
      }.to change {
        CLIHelper.processed_events
      }.to(
        array_including(
          a_hash_including(type: 'Foo', data: { foo: 'bar' })
        )
      )
    end
    it 're-locks existing subscription' do
      expect {
        subject
        # Let subscriptions to unlock and start
        sleep 3
      }.to change {
        existing_locked_subscription.reload.locked_by
      }.from(subscriptions_set.id).to(instance_of(Integer))
    end
  end
end
