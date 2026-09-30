# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeedStrategy::Collection do
  describe '.create' do
    subject { described_class.create(runners_query_options, connection, query_strategy, subscriptions_per_query:) }

    let(:runners_query_options) { {} }
    let(:connection) { PgEventstore.connection }
    let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }
    let(:subscriptions_per_query) { 2 }

    context 'when runners are absent' do
      it { is_expected.to be_empty }
    end

    context 'when runners are present' do
      let(:runners_query_options) { [runner1, runner2, runner3, runner4, runner5].to_h { [_1, query_options] } }
      let(:query_options) { { from_position: 1, max_count: 10, resolve_link_tos: false } }

      let(:runner1) { PgEventstore::SubscriptionRunner.allocate }
      let(:runner2) { PgEventstore::SubscriptionRunner.allocate }
      let(:runner3) { PgEventstore::SubscriptionRunner.allocate }
      let(:runner4) { PgEventstore::ReplicaSubscriptionRunner.allocate }
      let(:runner5) { PgEventstore::ReplicaSubscriptionRunner.allocate }

      it 'creates collection of three strategies, with up to subscriptions_per_query runners each' do
        aggregate_failures do
          expect(subject.size).to eq(3)
          expect(subject[0].instance_variable_get(:@runners_query_options)).to eq(
            runner1 => query_options, runner2 => query_options
          )
          expect(subject[0]).to be_a(PgEventstore::SubscriptionFeedStrategy::IndexReadStrategy)
          expect(subject[1].instance_variable_get(:@runners_query_options)).to eq(runner3 => query_options)
          expect(subject[1]).to be_a(PgEventstore::SubscriptionFeedStrategy::IndexReadStrategy)
          expect(subject[2].instance_variable_get(:@runners_query_options)).to eq(
            runner4 => query_options, runner5 => query_options
          )
          expect(subject[2]).to be_a(PgEventstore::SubscriptionFeedStrategy::ReplicationStrategy)
        end
      end
    end
  end
end
