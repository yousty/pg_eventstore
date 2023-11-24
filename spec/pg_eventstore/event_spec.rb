# frozen_string_literal: true

RSpec.describe PgEventstore::Event do
  subject { instance }

  let(:instance) { described_class.new }

  describe 'attributes' do
    it { is_expected.to have_attribute(:id) }
    it { is_expected.to have_attribute(:type) }
    it { is_expected.to have_attribute(:global_position) }
    it { is_expected.to have_attribute(:context) }
    it { is_expected.to have_attribute(:stream_name) }
    it { is_expected.to have_attribute(:stream_id) }
    it { is_expected.to have_attribute(:stream_revision) }
    it { is_expected.to have_attribute(:data) }
    it { is_expected.to have_attribute(:metadata) }
    it { is_expected.to have_attribute(:link_id) }
    it { is_expected.to have_attribute(:created_at) }
  end

  describe "#stream" do
    subject { instance.stream }

    let(:instance) { described_class.new(context: 'SomeContext', stream_name: 'SomeStream', stream_id: '123') }

    it { is_expected.to be_a(PgEventstore::Stream) }
    it 'has correct attributes' do
      aggregate_failures do
        expect(subject.context).to eq(instance.context)
        expect(subject.stream_name).to eq(instance.stream_name)
        expect(subject.stream_id).to eq(instance.stream_id)
      end
    end
  end

  describe '#==' do
    subject { instance == another_instance }

    let(:id) { SecureRandom.uuid }
    let(:instance) { described_class.new(id: id, type: 'SomeEvent') }
    let(:another_instance) { described_class.new(id: id, type: 'SomeEvent') }

    context 'when all attributes match' do
      it { is_expected.to eq(true) }
    end

    context 'when some attribute does not match' do
      before do
        another_instance.data = { foo: :bar}
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

    let(:instance) { described_class.new(link_id: 1) }

    context 'when #link_id is present' do
      it { is_expected.to eq(true) }
    end

    context 'when #link_id is nil' do
      let(:instance) { described_class.new(id: SecureRandom.uuid) }

      it { is_expected.to eq(false) }
    end
  end
end
