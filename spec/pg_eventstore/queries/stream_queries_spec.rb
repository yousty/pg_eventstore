# frozen_string_literal: true

RSpec.describe PgEventstore::StreamQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#find_stream' do
    subject { instance.find_stream(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-str', stream_id: '1') }

    context 'when stream exists' do
      before do
        instance.create_stream(stream)
      end

      it 'returns it' do
        aggregate_failures do
          is_expected.to eq(stream)
          expect(subject.id).to be_an(Integer)
        end
      end
    end

    context 'when stream does not exist' do
      it { is_expected.to eq(nil) }
    end
  end

  describe '#create_stream' do
    subject { instance.create_stream(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-str', stream_id: '1') }

    context 'when stream does not exist' do
      it 'creates it' do
        expect { subject }.to change { instance.find_stream(stream) }.from(nil).to(kind_of(PgEventstore::Stream))
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject.id).to be_a(Integer)
          expect(subject.context).to eq(stream.context)
          expect(subject.stream_name).to eq(stream.stream_name)
          expect(subject.stream_id).to eq(stream.stream_id)
        end
      end
    end

    context 'when stream already exists' do
      before do
        instance.create_stream(stream)
      end

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end
  end

  describe '#find_or_create_stream' do
    subject { instance.find_or_create_stream(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-str', stream_id: '1') }

    context 'when stream does not exist' do
      it 'creates it' do
        expect { subject }.to change { instance.find_stream(stream) }.from(nil).to(kind_of(PgEventstore::Stream))
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject.id).to be_a(Integer)
          expect(subject.context).to eq(stream.context)
          expect(subject.stream_name).to eq(stream.stream_name)
          expect(subject.stream_id).to eq(stream.stream_id)
        end
      end
    end

    context 'when stream exists' do
      before do
        instance.create_stream(stream)
      end

      it 'returns it' do
        aggregate_failures do
          is_expected.to eq(stream)
          expect(subject.id).to be_an(Integer)
        end
      end
    end
  end

  describe '#update_stream_revision' do
    subject { instance.update_stream_revision(stream, revision) }

    let(:stream) do
      instance.create_stream(PgEventstore::Stream.new(context: 'ctx', stream_name: 'some-str', stream_id: '1'))
    end
    let(:revision) { 3 }

    it 'updates #stream_revision' do
      expect { subject }.to change { instance.find_stream(stream).stream_revision }.to(3)
    end
  end

  describe '#find_by_ids' do
    subject { instance.find_by_ids(ids) }

    let(:ids) { [] }

    context 'when empty array is provided' do
      it { is_expected.to eq([]) }
    end

    context 'when array of ids is given' do
      let(:ids) { [1, 2, stream.id] }

      let(:stream) do
        instance.create_stream(PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1'))
      end

      it 'returns existing event types' do
        is_expected.to(
          eq(
            [{
               'id' => stream.id,
               'context' => 'FooCtx',
               'stream_name' => 'Foo',
               'stream_id' => '1',
               'stream_revision' => -1
             }]
          )
        )
      end
    end
  end
end
