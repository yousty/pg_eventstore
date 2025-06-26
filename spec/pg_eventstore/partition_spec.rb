# frozen_string_literal: true

RSpec.describe PgEventstore::Partition do
  subject { instance }

  let(:instance) { described_class.new(id: 1, context: 'FooCtx', table_name: 'events_123') }

  describe 'attributes' do
    it { is_expected.to have_attribute(:id) }
    it { is_expected.to have_attribute(:context) }
    it { is_expected.to have_attribute(:stream_name) }
    it { is_expected.to have_attribute(:event_type) }
    it { is_expected.to have_attribute(:table_name) }
  end
end
