# frozen_string_literal: true

RSpec.describe PgEventstore::Middleware::EventTracing do
  before do
    PgEventstore.configure do |config|
      config.middlewares = { event_trace: PgEventstore::Middleware::EventTracing.new }
    end
  end

  describe 'persisting and reading event' do
    subject { PgEventstore.client.append_to_stream(stream, event) }

    let(:event) { PgEventstore::Event.new }
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    context 'when caused_by is not provided' do
      it 'assigns correlation_id' do
        aggregate_failures do
          expect(subject.correlation_id).to be_a(String)
          expect(subject.metadata[described_class::CORRELATION_ID_KEY]).to eq(subject.correlation_id)
        end
      end
      it 'does not assign causation_id' do
        aggregate_failures do
          expect(subject.causation_id).to eq(nil)
          expect(subject.metadata.keys).not_to include(described_class::CAUSATION_ID_KEY)
        end
      end
      it 'adds correlation_id to the list of feature markers' do
        expect(subject.feature_markers).to eq([described_class.correlation_marker(subject.correlation_id)])
      end
      it 'marks event with correlation_id' do
        searched_by_correlation_id = PgEventstore.client.read(
          PgEventstore::Stream.all_stream, options: { filter: { event_types: [{ markers: [subject.correlation_id] }] } }
        ).first
        expect(subject).to eq(searched_by_correlation_id)
      end
    end


    context 'when caused_by is provided' do
      let(:caused_by) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }

      before do
        event.caused_by = caused_by
      end

      it 'assigns correlation_id' do
        aggregate_failures do
          expect(subject.correlation_id).to be_a(String)
          expect(subject.metadata[described_class::CORRELATION_ID_KEY]).to eq(subject.correlation_id)
          expect(subject.correlation_id).to eq(caused_by.correlation_id)
        end
      end
      it 'assigns causation_id' do
        aggregate_failures do
          expect(subject.causation_id).to eq(caused_by.id)
          expect(subject.metadata[described_class::CAUSATION_ID_KEY]).to eq(caused_by.id)
        end
      end
      it 'adds correlation_id and causation_id to the list of feature markers' do
        expect(subject.feature_markers).to(
          eq(
            [
              described_class.causation_marker(subject.causation_id),
              described_class.correlation_marker(subject.correlation_id),
            ]
          )
        )
      end
      it 'marks event with correlation_id properly' do
        searched_by_correlation_id = PgEventstore.client.read(
          PgEventstore::Stream.all_stream, options: { filter: { event_types: [{ markers: [subject.correlation_id] }] } }
        ).last
        expect(subject).to eq(searched_by_correlation_id)
      end
      it 'marks event with causation_id properly' do
        searched_by_causation_id = PgEventstore.client.read(
          PgEventstore::Stream.all_stream, options: { filter: { event_types: [{ markers: [subject.causation_id] }] } }
        ).first
        expect(subject).to eq(searched_by_causation_id)
      end
    end
  end

  describe '#serialize' do
    subject { described_class.new.serialize(event) }

    let(:event) { PgEventstore::Event.new }
    let(:uuid1) { '00000000-0000-0000-0000-000000000001' }
    let(:uuid2) { '00000000-0000-0000-0000-000000000002' }
    let(:uuid3) { '00000000-0000-0000-0000-000000000002' }

    before do
      allow(SecureRandom).to receive(:uuid_v7).and_return(uuid1, uuid2, uuid3)
    end

    context 'when #caused_by is not assigned' do
      it 'does not assign #causation_id, assigns #correlation_id' do
        subject
        aggregate_failures do
          expect(event.causation_id).to eq(nil)
          expect(event.correlation_id).to eq(uuid2)
          expect(event.metadata).to eq(described_class::CORRELATION_ID_KEY => uuid2)
          expect(event.feature_markers).to eq([described_class.correlation_marker(uuid2)])
        end
      end
    end

    context 'when #caused_by is assigned' do
      let(:caused_by) { PgEventstore::Event.new(id: uuid3) }

      before do
        event.caused_by = caused_by
      end

      it 'assigns #causation_id, assigns #correlation_id' do
        subject
        aggregate_failures do
          expect(event.causation_id).to eq(caused_by.id)
          expect(event.correlation_id).to eq(uuid2)
          expect(event.metadata).to(
            eq(described_class::CORRELATION_ID_KEY => uuid2, described_class::CAUSATION_ID_KEY => uuid3)
          )
          expect(event.feature_markers).to(
            eq(
              [
                described_class.causation_marker(uuid3),
                described_class.correlation_marker(uuid2),
              ]
            )
          )
        end
      end
    end
  end

  describe '#deserialize' do
    subject { described_class.new.deserialize(event) }

    let(:event) { PgEventstore::Event.new }

    context 'when metadata does not contain correlation/causation id' do
      it 'does not assign them' do
        subject
        aggregate_failures do
          expect(event.causation_id).to eq(nil)
          expect(event.correlation_id).to eq(nil)
        end
      end
      it 'does not change #feature_markers array' do
        subject
        expect(event.feature_markers).to eq([])
      end
    end

    context 'when metadata contains correlation id' do
      let(:correlation_id) { '00000000-0000-0000-0000-000000000001' }

      before do
        event.metadata[described_class::CORRELATION_ID_KEY] = correlation_id
      end

      it 'assigns #correlation_id, does not assign #causation_id' do
        subject
        aggregate_failures do
          expect(event.causation_id).to eq(nil)
          expect(event.correlation_id).to eq(correlation_id)
        end
      end
      it 'adds correlation id into #feature_markers array' do
        subject
        expect(event.feature_markers).to eq([described_class.correlation_marker(correlation_id)])
      end
    end

    context 'when metadata contains causation id' do
      let(:causation_id) { '00000000-0000-0000-0000-000000000001' }

      before do
        event.metadata[described_class::CAUSATION_ID_KEY] = causation_id
      end

      it 'does not assign #correlation_id, assigns #causation_id' do
        subject
        aggregate_failures do
          expect(event.causation_id).to eq(causation_id)
          expect(event.correlation_id).to eq(nil)
        end
      end
      it 'adds causation id into #feature_markers array' do
        subject
        expect(event.feature_markers).to eq([described_class.causation_marker(causation_id)])
      end
    end

    context 'when metadata contains causation and correlation id' do
      let(:causation_id) { '00000000-0000-0000-0000-000000000001' }
      let(:correlation_id) { '00000000-0000-0000-0000-000000000002' }

      before do
        event.metadata[described_class::CAUSATION_ID_KEY] = causation_id
        event.metadata[described_class::CORRELATION_ID_KEY] = correlation_id
      end

      it 'assigns #correlation_id, assigns #causation_id' do
        subject
        aggregate_failures do
          expect(event.causation_id).to eq(causation_id)
          expect(event.correlation_id).to eq(correlation_id)
        end
      end
      it 'adds causation and correlation ids into #feature_markers array' do
        subject
        expect(event.feature_markers).to(
          eq(
            [
              described_class.causation_marker(causation_id),
              described_class.correlation_marker(correlation_id),
            ]
          )
        )
      end
    end
  end
end
