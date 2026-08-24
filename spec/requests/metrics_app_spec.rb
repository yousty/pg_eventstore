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
        select coalesce(max(subscription_position), 0) as position from event_subscription_positions
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

  describe 'set scoping' do
    include_context 'with subscriptions and events'

    it 'reports every set when no set param is given' do
      get '/subscriptions/health'
      aggregate_failures do
        expect(last_response.body).to include('set="FooSet"')
        expect(last_response.body).to include('set="BarSet"')
      end
    end

    it 'reports only the requested set' do
      get '/subscriptions/health', set: 'FooSet'
      aggregate_failures do
        expect(last_response.body).to include('set="FooSet"')
        expect(last_response.body).not_to include('set="BarSet"')
      end
    end

    it 'reports several requested sets' do
      get '/subscriptions/health?set=FooSet&set=BarSet'
      aggregate_failures do
        expect(last_response.body).to include('set="FooSet"')
        expect(last_response.body).to include('set="BarSet"')
      end
    end

    it 'reports nothing for a set which does not exist' do
      get '/subscriptions/health', set: 'NoSuchSet'
      aggregate_failures do
        expect(last_response).to be_ok
        expect(last_response.body).not_to include('set="FooSet"')
      end
    end

    it 'ignores an empty set param' do
      get '/subscriptions/health', set: ''
      expect(last_response.body).to include('set="FooSet"')
    end
  end

  describe 'GET /subscriptions' do
    subject { get '/subscriptions' }

    include_context 'with subscriptions and events'

    it 'serves every family of the domain with the prometheus content type' do
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

  describe 'GET /' do
    subject { get '/' }

    # No route serves every domain at once. "/metrics" is the Prometheus convention, so a route there would invite
    # scrape jobs by reflex - and each such scrape would pay for every query, defeating the per-path split.
    it 'is not served' do
      subject
      expect(last_response.status).to eq(404)
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

    # Rows of the subscriptions table are never removed, so an unscoped scrape reports handlers that no longer run.
    # Filtering them out by recency was dropped: subscriptions.updated_at has no index and can not get one without
    # losing HOT updates, so the condition forced a sequential scan. Scoping is done by set instead.
    it 'reports subscriptions which are neither locked nor recently updated' do
      subject
      expect(last_response.body).to include('Orphan')
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
    before do
      # Make the default config broken by leaving it no connections, so it is unmistakable which config was used.
      PgEventstore.configure do |config|
        config.connection_pool_size = 0
        config.connection_pool_timeout = 1
      end
      PgEventstore.configure(name: :working) do |config|
        config.pg_uri = PgEventstore.config.pg_uri
        config.connection_pool_size = 2
      end
    end

    it 'queries the config named by the config param' do
      get '/subscriptions', config: 'working'
      expect(last_response).to be_ok
    end

    it 'falls back to the default config when the requested one does not exist' do
      get '/subscriptions', config: 'no-such-config'
      aggregate_failures do
        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('ConnectionPool::TimeoutError')
      end
    end

    it 'uses the default config when no config param is given' do
      get '/subscriptions'
      aggregate_failures do
        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('ConnectionPool::TimeoutError')
      end
    end
  end
end
