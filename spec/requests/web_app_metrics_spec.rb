# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Application, type: :request do
  let(:app) { described_class }

  describe 'GET /metrics' do
    subject { get '/metrics' }

    it 'serves all metric families with the prometheus content type' do
      subject
      aggregate_failures do
        expect(last_response).to be_ok
        expect(last_response.content_type).to eq(PgEventstore::Web::Metrics::Formatter::CONTENT_TYPE)
        expect(last_response.body).to include('pg_eventstore_subscription_lag_events')
        expect(last_response.body).to include('pg_eventstore_store_frontier_position')
      end
    end
  end

  describe 'GET /metrics/subscriptions/latency' do
    subject { get '/metrics/subscriptions/latency' }

    let(:subscriptions_set) { SubscriptionsSetHelper.create(name: 'MetricsSet') }
    let(:subscription) { SubscriptionsHelper.create(set: 'FooSet', name: 'Foo::Builder') }

    before do
      PgEventstore.connection.with do |conn|
        conn.exec_params(
          'update subscriptions set locked_by = $1 where id = $2', [subscriptions_set.id, subscription.id]
        )
      end
    end

    it 'serves latency metrics of locked subscriptions' do
      subject
      aggregate_failures do
        expect(last_response).to be_ok
        expect(last_response.body).to include('pg_eventstore_subscription_lag_events{set="FooSet",name="Foo::Builder"}')
      end
    end
  end
end
