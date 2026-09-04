# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Metrics::Formatter do
  subject { instance.call(families) }

  let(:instance) { described_class.new }

  describe '#call' do
    let(:family) do
      PgEventstore::Web::Metrics::MetricFamily.new(
        name: 'pg_eventstore_subscription_lag_events', type: 'gauge', help: 'Some help.'
      )
    end
    let(:families) { [family] }

    context 'when a family has no samples' do
      it 'renders only the header' do
        is_expected.to eq(<<~TEXT)
          # HELP pg_eventstore_subscription_lag_events Some help.
          # TYPE pg_eventstore_subscription_lag_events gauge
        TEXT
      end
    end

    context 'when a family has samples' do
      before do
        family.add_sample(labels: { set: 'FooSet', name: 'Foo::Builder' }, value: 12)
        family.add_sample(labels: { set: 'BarSet', name: 'Bar::Builder' }, value: 0.5)
      end

      it 'renders one line per sample' do
        is_expected.to eq(<<~TEXT)
          # HELP pg_eventstore_subscription_lag_events Some help.
          # TYPE pg_eventstore_subscription_lag_events gauge
          pg_eventstore_subscription_lag_events{set="FooSet",name="Foo::Builder"} 12
          pg_eventstore_subscription_lag_events{set="BarSet",name="Bar::Builder"} 0.5
        TEXT
      end
    end

    context 'when a sample has no labels' do
      before do
        family.add_sample(labels: {}, value: 42)
      end

      it 'renders the bare metric name' do
        is_expected.to include("\npg_eventstore_subscription_lag_events 42\n")
      end
    end

    context 'when a label value contains characters special to the exposition format' do
      before do
        family.add_sample(labels: { name: %(Foo\\Bar"Baz\nQux) }, value: 1)
      end

      it 'escapes them' do
        is_expected.to include('{name="Foo\\\\Bar\\"Baz\\nQux"}')
      end
    end

    context 'when multiple families are given' do
      let(:another_family) do
        PgEventstore::Web::Metrics::MetricFamily.new(
          name: 'pg_eventstore_store_frontier_position', type: 'gauge', help: 'Another help.'
        )
      end
      let(:families) { [family, another_family] }

      it 'renders them separated by a newline' do
        is_expected.to eq(<<~TEXT)
          # HELP pg_eventstore_subscription_lag_events Some help.
          # TYPE pg_eventstore_subscription_lag_events gauge
          # HELP pg_eventstore_store_frontier_position Another help.
          # TYPE pg_eventstore_store_frontier_position gauge
        TEXT
      end
    end
  end
end
