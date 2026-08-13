# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Metrics::Application, type: :request do
  let(:app) { described_class }

  def update_subscription(id, attrs)
    assignments = attrs.keys.map.with_index(1) { |key, index| "#{key} = $#{index}" }.join(', ')
    PgEventstore.connection.with do |conn|
      conn.exec_params("update subscriptions set #{assignments} where id = $#{attrs.size + 1}", [*attrs.values, id])
    end
  end

  # @return [Integer] current subscription positions frontier
  def frontier_position
    PgEventstore.connection.with do |conn|
      conn.exec(<<~SQL).first['position']
        select case when is_called then last_value else 0 end as position
        from event_subscription_positions_subscription_position_seq
      SQL
    end
  end

  # @param name [String]
  # @param labels [String, nil]
  # @return [String, nil]
  def metric_value(name, labels = nil)
    pattern = labels ? /^#{Regexp.escape(name)}\{#{Regexp.escape(labels)}\} (.+)$/ : /^#{Regexp.escape(name)} (.+)$/
    last_response.body[pattern, 1]
  end

  shared_context 'with subscriptions and events' do
    let(:subscriptions_set) { SubscriptionsSetHelper.create(name: 'MetricsSet') }
    let(:caught_up_subscription) { SubscriptionsHelper.create(set: 'FooSet', name: 'CaughtUp') }
    let(:lagging_subscription) { SubscriptionsHelper.create(set: 'FooSet', name: 'Lagging') }
    let(:orphan_subscription) { SubscriptionsHelper.create(set: 'BarSet', name: 'Orphan') }
    let(:stream) { PgEventstore::Stream.new(context: 'MetricsCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events_number) { 3 }
    # Memoized in the before hook - before and after the events are appended respectively
    let(:position_before_events) { frontier_position }
    let(:frontier) { frontier_position }

    before do
      position_before_events
      events = Array.new(events_number) { PgEventstore::Event.new(type: 'SomethingHappened', data: {}) }
      PgEventstore.client.append_to_stream(stream, events)
      PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection).assign_subscription_position
      frontier

      update_subscription(
        caught_up_subscription.id,
        { locked_by: subscriptions_set.id, current_position: frontier, state: 'running',
          total_processed_events: 120, average_event_processing_time: 0.025 }
      )
      update_subscription(
        lagging_subscription.id,
        { locked_by: subscriptions_set.id, current_position: position_before_events, state: 'running' }
      )
      update_subscription(orphan_subscription.id, { updated_at: Time.now.utc - 7200 })
    end
  end

  describe 'authentication' do
    subject { get '/' }

    context 'when auth token env variable is not set' do
      it 'serves metrics without authentication' do
        subject
        expect(last_response).to be_ok
      end
    end

    context 'when auth token env variable is set' do
      around do |example|
        ENV[described_class::AUTH_TOKEN_ENV_VAR] = 'super-secret'
        example.run
      ensure
        ENV.delete(described_class::AUTH_TOKEN_ENV_VAR)
      end

      it 'responds with 401 without the token' do
        subject
        expect(last_response.status).to eq(401)
      end

      it 'responds with 401 for a wrong token' do
        header 'Authorization', 'Bearer wrong'
        subject
        expect(last_response.status).to eq(401)
      end

      it 'serves metrics for the correct token' do
        header 'Authorization', 'Bearer super-secret'
        subject
        expect(last_response).to be_ok
      end
    end
  end

  describe 'GET /' do
    subject { get '/' }

    include_context 'with subscriptions and events'

    it 'serves all metric families with the prometheus content type' do
      subject
      aggregate_failures do
        expect(last_response).to be_ok
        expect(last_response.content_type).to eq(PgEventstore::Web::Metrics::Formatter::CONTENT_TYPE)
        expect(last_response.body).to include('pg_eventstore_subscription_lag_events')
        expect(last_response.body).to include('pg_eventstore_subscription_heartbeat_age_seconds')
        expect(last_response.body).to include('pg_eventstore_subscription_processed_events_total')
      end
    end
  end

  describe 'GET /subscriptions/latency' do
    subject { get '/subscriptions/latency' }

    include_context 'with subscriptions and events'

    it 'reports lag against the subscription positions frontier' do
      subject
      aggregate_failures do
        expect(metric_value('pg_eventstore_subscription_lag_events', 'set="FooSet",name="CaughtUp"')).to eq('0')
        expect(metric_value('pg_eventstore_subscription_lag_events', 'set="FooSet",name="Lagging"')).
          to eq(events_number.to_s)
      end
    end

    it 'reports the age of the oldest unprocessed event' do
      subject
      aggregate_failures do
        expect(metric_value('pg_eventstore_subscription_lag_seconds', 'set="FooSet",name="CaughtUp"')).to eq('0.0')
        expect(metric_value('pg_eventstore_subscription_lag_seconds', 'set="FooSet",name="Lagging"').to_f).
          to be_between(0.001, 60)
      end
    end

    it 'reports store positions' do
      subject
      aggregate_failures do
        expect(metric_value('pg_eventstore_store_frontier_position')).to eq(frontier.to_s)
        expect(metric_value('pg_eventstore_store_head_global_position').to_i).to be >= frontier
      end
    end

    it 'does not report subscriptions which are not locked and were not updated recently' do
      subject
      expect(last_response.body).not_to include('Orphan')
    end

    context 'with a live subscription whose filter matches none of the appended events' do
      subject { get '/subscriptions/latency' }

      let(:manager) { PgEventstore.subscriptions_manager(subscription_set: 'FilteredSet') }
      let(:handler) { proc { |event| } }
      let(:stream) { PgEventstore::Stream.new(context: 'MetricsCtx', stream_name: 'Foo', stream_id: '2') }
      let(:events) { Array.new(3) { PgEventstore::Event.new(type: 'SomethingHappened', data: {}) } }

      # @return [Integer, nil]
      def current_position
        PgEventstore.connection.with do |conn|
          conn.exec_params(
            'select current_position from subscriptions where set = $1 and name = $2', %w[FilteredSet FilteredOut]
          ).first&.dig('current_position')
        end
      end

      before do
        PgEventstore.configure { |config| config.subscription_pull_interval = 0.2 }
        manager.subscribe('FilteredOut', handler:, options: { filter: { event_types: ['UnrelatedType'] } })
        manager.start
        PgEventstore.client.append_to_stream(stream, events)
        dv.wait_until(timeout: 5) { current_position.to_i >= frontier_position }
      end

      after do
        manager.stop
      end

      # The subscription never processes a single event - the feeder advances its checkpoint through the
      # non-matching range via checkpoint chunks. The metric must not present the store's unrelated traffic as
      # this subscription's lag.
      it 'reports zero lag once the checkpoint caught up' do
        subject
        aggregate_failures do
          expect(metric_value('pg_eventstore_subscription_lag_events', 'set="FilteredSet",name="FilteredOut"')).
            to eq('0')
          expect(metric_value('pg_eventstore_subscription_lag_seconds', 'set="FilteredSet",name="FilteredOut"')).
            to eq('0.0')
        end
      end
    end
  end

  describe 'GET /subscriptions/health' do
    subject { get '/subscriptions/health' }

    include_context 'with subscriptions and events'

    context 'with a regular locked subscription' do
      it 'reports state, lock and heartbeat age' do
        subject
        aggregate_failures do
          expect(metric_value('pg_eventstore_subscription_state', 'set="FooSet",name="CaughtUp",state="running"')).
            to eq('1')
          expect(metric_value('pg_eventstore_subscription_locked', 'set="FooSet",name="CaughtUp"')).to eq('1')
          expect(metric_value('pg_eventstore_subscription_heartbeat_age_seconds', 'set="FooSet",name="CaughtUp"').to_f).
            to be_between(0, 60)
          expect(metric_value('pg_eventstore_subscription_restarts_total', 'set="FooSet",name="CaughtUp"')).to eq('0')
        end
      end
    end

    context 'with a subscription which died without releasing its lock' do
      before do
        update_subscription(
          lagging_subscription.id, { updated_at: Time.now.utc - 7200, last_error_occurred_at: Time.now.utc - 7200 }
        )
      end

      it 'still reports it, with a stale heartbeat' do
        subject
        aggregate_failures do
          expect(metric_value('pg_eventstore_subscription_heartbeat_age_seconds', 'set="FooSet",name="Lagging"').to_f).
            to be > 7000
          expect(metric_value('pg_eventstore_subscription_last_error_age_seconds', 'set="FooSet",name="Lagging"').to_f).
            to be > 7000
        end
      end
    end

    context 'with a subscription which never failed' do
      it 'does not report last error age for it' do
        subject
        expect(metric_value('pg_eventstore_subscription_last_error_age_seconds', 'set="FooSet",name="CaughtUp"')).
          to eq(nil)
      end
    end
  end

  describe 'GET /subscriptions/throughput' do
    subject { get '/subscriptions/throughput' }

    include_context 'with subscriptions and events'

    it 'reports total processed events' do
      subject
      expect(metric_value('pg_eventstore_subscription_processed_events_total', 'set="FooSet",name="CaughtUp"')).
        to eq('120')
    end

    it 'reports handler capacity when average processing time is known' do
      subject
      expect(metric_value('pg_eventstore_subscription_capacity_events_per_second',
                          'set="FooSet",name="CaughtUp"').to_f).
        to be_within(1.0).of(40.0)
    end

    it 'does not report handler capacity when average processing time is unknown' do
      subject
      expect(metric_value('pg_eventstore_subscription_capacity_events_per_second', 'set="FooSet",name="Lagging"')).
        to eq(nil)
    end
  end

  describe 'config resolution' do
    subject { get '/' }

    before do
      # Make default config broken by setting available connections to zero to demonstrate the difference between it
      # and the metrics config
      PgEventstore.configure do |config|
        config.connection_pool_size = 0
        config.connection_pool_timeout = 1
      end
    end

    context 'when metrics config is defined' do
      before do
        PgEventstore.configure(name: described_class::DEFAULT_METRICS_CONFIG) do |config|
          config.pg_uri = PgEventstore.config.pg_uri
          config.connection_pool_size = 2
        end
      end

      it 'uses it' do
        subject
        expect(last_response).to be_ok
      end
    end

    context 'when metrics config is not defined' do
      it 'uses default config' do
        subject
        aggregate_failures do
          expect(last_response.status).to eq(500)
          expect(last_response.body).to include('ConnectionPool::TimeoutError')
        end
      end
    end
  end
end
