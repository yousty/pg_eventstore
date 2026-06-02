# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeedStrategy::Collection do
  describe '.create' do
    subject { described_class.create(runners, connection, query_strategy, subscriptions_per_query:) }

    let(:runners) { [] }
    let(:connection) { PgEventstore.connection }
    let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }
    let(:subscriptions_per_query) { 2 }

    context 'when runners are absent' do
      it { is_expected.to be_empty }
    end

    context 'when runners are present' do
      let(:runners) { [runner1, runner2, runner3] }
      let(:runner1) { PgEventstore::SubscriptionRunner.allocate }
      let(:runner2) { PgEventstore::SubscriptionRunner.allocate }
      let(:runner3) { PgEventstore::SubscriptionRunner.allocate }

      it 'creates collection of two strategies, with up to subscriptions_per_query runners each' do
        aggregate_failures do
          expect(subject.size).to eq(2)
          expect(subject.first.instance_variable_get(:@runners)).to eq([runner1, runner2])
          expect(subject.last.instance_variable_get(:@runners)).to eq([runner3])
        end
      end
    end
  end
end
