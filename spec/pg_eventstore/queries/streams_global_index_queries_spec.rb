# frozen_string_literal: true

RSpec.describe PgEventstore::StreamsGlobalIndexQueries do
  let(:instance) { described_class.new(PgEventstore.connection, query_strategy) }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

  describe '#find_or_create_by' do
    subject { instance.find_or_create_by(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }
    let!(:event_type_partition) { partition_queries.create_partitions(stream, 'Any') }

    context 'when StreamGlobalIndex exists' do
      let!(:existing_stream_idx) { instance.create(stream) }

      it 'returns it' do
        is_expected.to eq(existing_stream_idx)
      end
      it 'does not create another one' do
        expect { subject }.not_to change {
          query_strategy.exec('select count(*) as c_all from streams_global_index').first['c_all']
        }
      end
    end

    context 'when StreamGlobalIndex does not exist' do
      it 'creates it' do
        expect { subject }.to change {
          query_strategy.exec('select count(*) as c_all from streams_global_index').first['c_all']
        }.by(1)
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject.partition_id).to eq(event_type_partition['parent_stream_name_partition_id']).and be_a(Integer)
          expect(subject.stream_id).to eq(stream.stream_id)
          expect(subject.stream_revision).to eq(PgEventstore::Stream::NON_EXISTING_STREAM_REVISION)
          expect(subject.starting_position).to eq(PgEventstore::StreamGlobalIndex::INITIAL_STARTING_POSITION)
        end
      end
    end
  end

  describe '#find_by' do
    subject { instance.find_by(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

    before do
      partition_queries.create_partitions(stream, 'Any')
    end

    context 'when StreamGlobalIndex exists' do
      let!(:existing_stream_idx) { instance.create(stream) }

      it 'returns it' do
        is_expected.to eq(existing_stream_idx)
      end
    end

    context 'when StreamGlobalIndex does not exist' do
      it { is_expected.to eq(nil) }
    end
  end

  describe '#find_by!' do
    subject { instance.find_by!(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

    before do
      partition_queries.create_partitions(stream, 'Any')
    end

    context 'when StreamGlobalIndex exists' do
      let!(:existing_stream_idx) { instance.create(stream) }

      it 'returns it' do
        is_expected.to eq(existing_stream_idx)
      end
    end

    context 'when StreamGlobalIndex does not exist' do
      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::RecordNotFound)
      end
    end
  end

  describe '#update' do
    subject { instance.update(stream_idx.id, **attrs) }

    let(:stream_idx) { instance.create(stream) }
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }
    let(:attrs) { { starting_position: 123, stream_revision: 321 } }

    before do
      partition_queries.create_partitions(stream, 'Any')
      stream_idx
    end

    it 'updates given :starting_position' do
      expect { subject }.to change { instance.find_by(stream).starting_position }.to(123)
    end
    it 'updates given :stream_revision' do
      expect { subject }.to change { instance.find_by(stream).stream_revision }.to(321)
    end
  end

  describe '#create' do
    subject { instance.create(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }
    let!(:event_type_partition) { partition_queries.create_partitions(stream, 'Any') }

    it 'creates StreamGlobalIndex' do
      expect { subject }.to change {
        query_strategy.exec('select count(*) as c_all from streams_global_index').first['c_all']
      }.by(1)
    end
    it 'has correct attributes' do
      aggregate_failures do
        expect(subject.partition_id).to eq(event_type_partition['parent_stream_name_partition_id']).and be_a(Integer)
        expect(subject.stream_id).to eq(stream.stream_id)
        expect(subject.stream_revision).to eq(PgEventstore::Stream::NON_EXISTING_STREAM_REVISION)
        expect(subject.starting_position).to eq(PgEventstore::StreamGlobalIndex::INITIAL_STARTING_POSITION)
      end
    end
  end

  describe '#delete' do
    subject { instance.delete(id) }

    let(:id) { 1 }

    context 'when StreamGlobalIndex exists' do
      let(:id) { stream_idx.id }
      let(:stream_idx) { instance.create(stream) }
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      before do
        partition_queries.create_partitions(stream, 'Any')
        stream_idx
      end

      it 'deletes it' do
        expect { subject }.to change {
          query_strategy.exec('select count(*) as c_all from streams_global_index').first['c_all']
        }.by(-1)
      end
      it { is_expected.to eq(true) }
    end

    context 'when StreamGlobalIndex does not exist' do
      let(:another_stream_idx) { instance.create(stream) }
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      before do
        partition_queries.create_partitions(stream, 'Any')
        another_stream_idx
      end

      it 'does not delete anything' do
        expect { subject }.not_to change {
          query_strategy.exec('select count(*) as c_all from streams_global_index').first['c_all']
        }
      end
      it { is_expected.to eq(false) }
    end
  end

  describe '#stream_exists?' do
    subject { instance.stream_exists?(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    context 'when StreamGlobalIndex exists' do
      let(:stream_idx) { instance.create(stream) }
      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      before do
        partition_queries.create_partitions(stream, 'Any')
        stream_idx
      end

      it { is_expected.to eq(true) }
    end

    context 'when StreamGlobalIndex does not exist' do
      let(:another_stream_idx) { instance.create(another_stream) }
      let(:another_stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      before do
        partition_queries.create_partitions(another_stream, 'Any')
        another_stream_idx
      end

      it { is_expected.to eq(false) }
    end
  end

  describe '#stream_revision' do
    subject { instance.stream_revision(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    context 'when StreamGlobalIndex exists' do
      let(:stream_idx) { instance.create(stream) }
      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      before do
        partition_queries.create_partitions(stream, 'Any')
        stream_idx
        instance.update(stream_idx.id, stream_revision: 123)
      end

      it 'returns its revision' do
        is_expected.to eq(123)
      end
    end

    context 'when StreamGlobalIndex does not exist' do
      let(:another_stream_idx) { instance.create(another_stream) }
      let(:another_stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      before do
        partition_queries.create_partitions(another_stream, 'Any')
        another_stream_idx
      end

      it { is_expected.to eq(nil) }
    end
  end

  describe '#resolve_indexes' do
    subject { instance.resolve_indexes(indexes) }

    let(:indexes) { [] }

    context 'when indexes are empty' do
      it { is_expected.to eq([]) }
    end

    context 'when indexes are present' do
      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }
      let(:stream_idx1) { instance.find_by!(stream1) }
      let(:stream_idx2) { instance.find_by!(stream2) }
      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      let(:indexes) { [stream_idx1, stream_idx2] }

      before do
        partition_queries.create_partitions(stream1, 'Any')
        partition_queries.create_partitions(stream2, 'Any')
        stream_idx1 = instance.create(stream1)
        stream_idx2 = instance.create(stream2)
        instance.update(stream_idx1.id, stream_revision: 123, starting_position: 321)
        instance.update(stream_idx2.id, stream_revision: 223, starting_position: 322)
      end

      it 'resolves them to Stream-s' do
        aggregate_failures do
          is_expected.to be_an(Array)
          expect(subject.size).to eq(2)
          is_expected.to all be_a(PgEventstore::Stream)
        end
      end

      describe 'first Stream' do
        subject { super()[0] }

        it 'has correct attributes' do
          aggregate_failures do
            expect(subject.context).to eq(stream1.context)
            expect(subject.stream_name).to eq(stream1.stream_name)
            expect(subject.stream_id).to eq(stream1.stream_id)
            expect(subject.stream_revision).to eq(123)
            expect(subject.starting_position).to eq(321)
          end
        end
      end

      describe 'second Stream' do
        subject { super()[1] }

        it 'has correct attributes' do
          aggregate_failures do
            expect(subject.context).to eq(stream2.context)
            expect(subject.stream_name).to eq(stream2.stream_name)
            expect(subject.stream_id).to eq(stream2.stream_id)
            expect(subject.stream_revision).to eq(223)
            expect(subject.starting_position).to eq(322)
          end
        end
      end
    end
  end
end
