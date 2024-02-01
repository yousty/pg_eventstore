# frozen_string_literal: true

RSpec.describe PgEventstore::EventTypeQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#find_or_create_type' do
    subject { instance.find_or_create_type(type) }

    let(:type) { 'some event' }

    context 'when event type exists' do
      let!(:event_type_id) { instance.create_type(type) }

      it 'returns its id' do
        aggregate_failures do
          is_expected.to be_a(Integer)
          is_expected.to eq(event_type_id)
        end
      end
    end

    context 'when event type does not exist' do
      it 'creates it' do
        expect { subject }.to change {
          PgEventstore.connection.with { |c| c.exec('select count(*) from event_types') }.to_a.dig(0, 'count')
        }.by(1)
      end
      it 'returns its id' do
        aggregate_failures do
          is_expected.to be_a(Integer)
          is_expected.to eq(instance.find_type(type))
        end
      end
    end
  end

  describe '#find_type' do
    subject { instance.find_type(type) }

    let(:type) { 'some event' }

    context 'when event type exists' do
      let!(:event_type_id) { instance.create_type(type) }

      it 'returns its id' do
        aggregate_failures do
          is_expected.to be_a(Integer)
          is_expected.to eq(event_type_id)
        end
      end
    end

    context 'when event type does not exist' do
      it { is_expected.to eq(nil) }
    end
  end

  describe '#create_type' do
    subject { instance.create_type(type) }

    let(:type) { 'some event' }

    context 'when event type exists' do
      let!(:event_type_id) { instance.create_type(type) }

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    context 'when event type does not exist' do
      it 'creates it' do
        expect { subject }.to change {
          PgEventstore.connection.with { |c| c.exec('select count(*) from event_types') }.to_a.dig(0, 'count')
        }.by(1)
      end
      it 'returns its id' do
        aggregate_failures do
          is_expected.to be_a(Integer)
          is_expected.to eq(instance.find_type(type))
        end
      end
    end
  end

  describe '#include_event_types_ids' do
    subject { instance.include_event_types_ids(options) }

    let(:options) { { filter: { streams: [{ context: 'FooCtx' }] } } }

    context 'when filter by event types is absent' do
      it { is_expected.to eq(options) }
    end

    context 'when filter by event types is present' do
      let(:types) { %w[Foo Bar] }

      before do
        options[:filter][:event_types] = types
      end

      context 'when related events exist' do
        let!(:event_types_ids) { types.map { |type| instance.create_type(type) } }

        it 'replaces string representations with ids' do
          is_expected.to eq(filter: { streams: [{ context: 'FooCtx' }], event_type_ids: event_types_ids })
        end
        it 'does not change original hash' do
          expect { subject }.not_to change { options }
        end
      end

      context 'when related events does not exist' do
        it 'replaces string representations with nil' do
          is_expected.to eq(filter: { streams: [{ context: 'FooCtx' }], event_type_ids: [nil] })
        end
        it 'does not change original hash' do
          expect { subject }.not_to change { options }
        end
      end

      context 'when one of related events exists' do
        let!(:foo_type_id) { instance.create_type('Foo') }

        it 'replaces string representations with nil and event id' do
          is_expected.to eq(filter: { streams: [{ context: 'FooCtx' }], event_type_ids: [foo_type_id, nil] })
        end
        it 'does not change original hash' do
          expect { subject }.not_to change { options }
        end
      end
    end
  end

  describe '#find_by_ids' do
    subject { instance.find_by_ids(ids) }

    let(:ids) { [] }

    context 'when empty array is provided' do
      it { is_expected.to eq([]) }
    end

    context 'when array of ids is given' do
      let(:ids) { [1, 2, event_type_id] }

      let(:event_type_id) { instance.create_type('foo') }

      it 'returns existing event types' do
        is_expected.to eq([{ 'id' => event_type_id,  'type' => 'foo' }])
      end
    end
  end
end
