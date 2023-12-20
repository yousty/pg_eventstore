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
end
