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
    it { is_expected.to have_attribute(:link_global_position) }
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

    let(:instance) { described_class.new(link_global_position: 123) }

    context 'when #link_global_position is present' do
      it { is_expected.to eq(true) }
    end

    context 'when #link_global_position is nil' do
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

  describe '#hash' do
    let(:hash) { {} }
    let(:event1) { described_class.new(type: 'Foo', id:) }
    let(:event2) { described_class.new(type: 'Foo', id:) }
    let(:id) { SecureRandom.uuid_v7 }

    before do
      hash[event1] = :foo
    end

    context 'when events matches' do
      it 'recognizes second event' do
        expect(hash[event2]).to eq(:foo)
      end
    end

    context 'when events do not match' do
      let(:event2) { described_class.new(type: 'Bar') }

      it 'does not recognize second event' do
        expect(hash[event2]).to eq(nil)
      end
    end
  end

  describe '#dup' do
    subject { event.dup }

    let(:event) do
      described_class.new(
        id: SecureRandom.uuid,
        type: 'Foo',
        global_position: 1,
        stream:,
        stream_revision: 2,
        data: { foo: ['bar'] },
        metadata: { meta: [3] },
        link: link_event,
        created_at: Time.now.utc
      )
    end
    let(:link_event) do
      described_class.new(type: described_class::LINK_TYPE, link_global_position: 4, link_partition_id: 5)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    it 'creates copy of the given event' do
      aggregate_failures do
        expect(subject.__id__).not_to eq(event.__id__)
        expect(subject).to eq(event)
        expect(subject.link).to eq(event.link)
      end
    end
    it 'creates new nested objects' do
      cloned = subject
      event.data[:foo].push('baz')
      event.stream.instance_variable_set(:@context, 'FooCtx2')
      event.link.link_global_position = 42
      aggregate_failures do
        expect(cloned).not_to eq(event)
        expect(cloned.link).not_to eq(event.link)
      end
    end
  end
end
