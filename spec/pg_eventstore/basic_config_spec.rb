# frozen_string_literal: true

RSpec.describe PgEventstore::BasicConfig do
  subject { instance }

  let(:instance) { described_class.new(name: :my_awesome_config) }

  it { is_expected.to be_a(PgEventstore::Extensions::OptionsExtension) }
  it { expect(subject.name).to eq(:my_awesome_config) }
end
