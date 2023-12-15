# frozen_string_literal: true

RSpec.describe PgEventstore::Queries do
  let(:instance) { described_class.new }

  describe 'attributes' do
    subject { instance }

    it { is_expected.to have_attribute(:events) }
    it { is_expected.to have_attribute(:streams) }
    it { is_expected.to have_attribute(:transactions) }
  end
end
