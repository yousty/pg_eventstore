# frozen_string_literal: true

RSpec.describe PgEventstore::Event do
  subject { instance }

  let(:instance) { described_class.new }

  describe 'attributes' do
    it { is_expected.to have_attribute(:id) }
    it { is_expected.to have_attribute(:type).with_default_value('PgEventstore::Event') }
    it { is_expected.to have_attribute(:global_position) }
    it { is_expected.to have_attribute(:stream) }
    it { is_expected.to have_attribute(:stream_revision) }
    it { is_expected.to have_attribute(:data).with_default_value({}) }
    it { is_expected.to have_attribute(:metadata).with_default_value({}) }
    it { is_expected.to have_attribute(:link_id) }
    it { is_expected.to have_attribute(:link) }
    it { is_expected.to have_attribute(:created_at) }
  end

  describe '#==' do
    subject { instance == another_instance }

    let(:id) { SecureRandom.uuid }
    let(:instance) { described_class.new(id:, type: 'SomeEvent') }
    let(:another_instance) { described_class.new(id:, type: 'SomeEvent') }

    context 'when all attributes match' do
      it { is_expected.to eq(true) }
    end

    context 'when some attribute does not match' do
      before do
        another_instance.data = { foo: :bar }
      end

      it { is_expected.to eq(false) }
    end

    context 'when another instance is not an Event object' do
      let(:another_instance) { Object.new }

      it { is_expected.to eq(false) }
    end
  end

  describe '#link?' do
    subject { instance.link? }

    let(:instance) { described_class.new(link_id: SecureRandom.uuid) }

    context 'when #link_id is present' do
      it { is_expected.to eq(true) }
    end

    context 'when #link_id is nil' do
      let(:instance) { described_class.new(id: SecureRandom.uuid) }

      it { is_expected.to eq(false) }
    end
  end

  describe '#system?' do
    subject { instance.system? }

    let(:instance) { described_class.new(type: 'MyAwesomeEvent') }

    describe 'when type is just a regular event type' do
      it { is_expected.to eq(false) }
    end

    describe 'when type starts with "$" sign' do
      let(:instance) { described_class.new(type: '$MyAwesomeEvent') }

      it { is_expected.to eq(true) }
    end
  end
end
