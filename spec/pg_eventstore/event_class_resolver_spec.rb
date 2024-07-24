# frozen_string_literal: true

RSpec.describe PgEventstore::EventClassResolver do
  let(:instance) { described_class.new }

  describe '#call' do
    subject { instance.call(event_type) }

    let(:event_type) { 'SomeEvent' }

    context 'when event type matches existing class' do
      let(:event_class) { Class.new(PgEventstore::Event) }

      before do
        stub_const(event_type, event_class)
      end

      it { is_expected.to eq(SomeEvent) }
    end

    context 'when event type is nil' do
      let(:event_type) { nil }

      it { is_expected.to eq(PgEventstore::Event) }
    end

    context 'when event type can not be resolved' do
      let(:event_type) { 'SomethingFoo' }

      it { is_expected.to eq(PgEventstore::Event) }
    end
  end
end
