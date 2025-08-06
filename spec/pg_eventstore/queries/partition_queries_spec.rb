# frozen_string_literal: true

RSpec.describe PgEventstore::PartitionQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#create_context_partition' do
    subject { instance.create_context_partition(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }

    context 'when partition already exists' do
      before do
        instance.create_context_partition(stream)
      end

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    context 'when partition does not exist' do
      it 'creates partition record' do
        expect { subject }.to change {
          instance.context_partition(stream)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => nil, 'event_type' => nil, 'table_name' => 'contexts_81820a'
          )
        )
      end
      it 'creates partition table' do
        expect { subject }.to change {
          partition_table(instance.context_partition_name(stream))
        }.from(nil).to(a_hash_including('tablename' => 'contexts_81820a'))
      end
    end

    context 'when there is a table name collision' do
      let(:digests) { 'c4ca4f38a0b923820dcc509a6f75849b' }
      let(:another_stream) { PgEventstore::Stream.new(context: 'SomeCtx2', stream_name: 'SomeStream', stream_id: '1') }

      before do
        allow(Digest::MD5).to receive(:hexdigest).and_return(digests)
        instance.create_context_partition(another_stream)
      end

      it 'creates partition record' do
        expect { subject }.to change {
          instance.context_partition(stream)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => nil, 'event_type' => nil, 'table_name' => 'contexts_c4ca4g'
          )
        )
      end
      it 'creates partition table' do
        expect { subject }.to change {
          partition_table('contexts_c4ca4g')
        }.from(nil).to(a_hash_including('tablename' => 'contexts_c4ca4g'))
      end
    end
  end

  describe '#create_stream_name_partition' do
    subject { instance.create_stream_name_partition(stream, context_partition_name) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }
    let(:context_partition_name) { instance.create_context_partition(stream)['table_name'] }

    context 'when partition already exists' do
      before do
        instance.create_stream_name_partition(stream, context_partition_name)
      end

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    context 'when partition does not exist' do
      it 'creates partition record' do
        expect { subject }.to change {
          instance.stream_name_partition(stream)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => stream.stream_name, 'event_type' => nil,
            'table_name' => 'stream_names_ecb803'
          )
        )
      end
      it 'creates partition table' do
        expect { subject }.to change {
          partition_table(instance.stream_name_partition_name(stream))
        }.from(nil).to(a_hash_including('tablename' => 'stream_names_ecb803'))
      end
    end

    context 'when there is a table name collision' do
      let(:digests) { 'c4ca4f38a0b923820dcc509a6f75849b' }
      let(:another_stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream2', stream_id: '1') }

      before do
        allow(Digest::MD5).to receive(:hexdigest).and_return(digests)
        instance.create_stream_name_partition(another_stream, context_partition_name)
      end

      it 'creates partition record' do
        expect { subject }.to change {
          instance.stream_name_partition(stream)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => stream.stream_name, 'event_type' => nil,
            'table_name' => 'stream_names_c4ca4g'
          )
        )
      end
      it 'creates partition table' do
        expect { subject }.to change {
          partition_table('stream_names_c4ca4g')
        }.from(nil).to(a_hash_including('tablename' => 'stream_names_c4ca4g'))
      end
    end
  end

  describe '#create_event_type_partition' do
    subject { instance.create_event_type_partition(stream, event_type, stream_name_partition_name) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }
    let(:event_type) { 'SomethingChanged' }
    let(:stream_name_partition_name) do
      context_partition = instance.create_context_partition(stream)
      instance.create_stream_name_partition(stream, context_partition['table_name'])['table_name']
    end

    context 'when partition already exists' do
      before do
        instance.create_event_type_partition(stream, event_type, stream_name_partition_name)
      end

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    context 'when partition does not exist' do
      it 'creates partition record' do
        expect { subject }.to change {
          instance.event_type_partition(stream, event_type)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => stream.stream_name, 'event_type' => event_type,
            'table_name' => 'event_types_aeadd5'
          )
        )
      end
      it 'creates partition table' do
        expect { subject }.to change {
          partition_table(instance.event_type_partition_name(stream, event_type))
        }.from(nil).to(a_hash_including('tablename' => 'event_types_aeadd5'))
      end
    end

    context 'when there is a table name collision' do
      let(:digests) { 'c4ca4f38a0b923820dcc509a6f75849b' }
      let(:another_stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream2', stream_id: '1') }
      let(:another_event_type) { 'SomethingElseChanged' }

      before do
        allow(Digest::MD5).to receive(:hexdigest).and_return(digests)
        instance.create_event_type_partition(another_stream, another_event_type, stream_name_partition_name)
      end

      it 'creates partition record' do
        expect { subject }.to change {
          instance.event_type_partition(stream, event_type)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => stream.stream_name, 'event_type' => event_type,
            'table_name' => 'event_types_c4ca4g'
          )
        )
      end
      it 'creates partition table' do
        expect { subject }.to change {
          partition_table('event_types_c4ca4g')
        }.from(nil).to(a_hash_including('tablename' => 'event_types_c4ca4g'))
      end
    end
  end

  describe '#partition_required?' do
    subject { instance.partition_required?(stream, event_type) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }
    let(:event_type) { 'SomethingChanged' }
    let(:stream_name_partition_name) do
      context_partition = instance.create_context_partition(stream)
      instance.create_stream_name_partition(stream, context_partition['table_name'])['table_name']
    end

    context 'when related event type partition exists' do
      before do
        instance.create_event_type_partition(stream, event_type, stream_name_partition_name)
      end

      it { is_expected.to eq(false) }
    end

    context 'when related event type partition does not exist' do
      it { is_expected.to eq(true) }
    end
  end

  describe '#create_partitions' do
    subject { instance.create_partitions(stream, event_type) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }
    let(:event_type) { 'SomethingChanged' }

    shared_examples 'created context partition' do
      it 'creates context partition record' do
        expect { subject }.to change {
          instance.context_partition(stream)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => nil, 'event_type' => nil, 'table_name' => 'contexts_81820a'
          )
        )
      end
      it 'creates context partition table' do
        expect { subject }.to change {
          partition_table(instance.context_partition_name(stream))
        }.from(nil).to(a_hash_including('tablename' => 'contexts_81820a'))
      end
    end

    shared_examples 'created stream name partition' do
      it 'creates stream name partition record' do
        expect { subject }.to change {
          instance.stream_name_partition(stream)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => stream.stream_name, 'event_type' => nil,
            'table_name' => 'stream_names_ecb803'
          )
        )
      end
      it 'creates stream name partition table' do
        expect { subject }.to change {
          partition_table(instance.stream_name_partition_name(stream))
        }.from(nil).to(a_hash_including('tablename' => 'stream_names_ecb803'))
      end
    end

    shared_examples 'created event type partition' do
      it 'creates event type partition record' do
        expect { subject }.to change {
          instance.event_type_partition(stream, event_type)
        }.to(
          a_hash_including(
            'context' => stream.context, 'stream_name' => stream.stream_name, 'event_type' => event_type,
            'table_name' => 'event_types_aeadd5'
          )
        )
      end
      it 'creates event type partition table' do
        expect { subject }.to change {
          partition_table(instance.event_type_partition_name(stream, event_type))
        }.from(nil).to(a_hash_including('tablename' => 'event_types_aeadd5'))
      end
    end

    shared_examples 'skips context partition' do
      it 'does not create context partition record' do
        expect { subject }.not_to change {
          PgEventstore.connection.with do |c|
            c.exec('select * from partitions where context is not null and stream_name is null and event_type is null')
          end.to_a
        }
      end
      it 'does not create context partition table' do
        expect { subject }.not_to change {
          PgEventstore.connection.with do |c|
            c.exec("select * from pg_tables where tablename like 'contexts_%'")
          end.to_a
        }
      end
    end

    shared_examples 'skips stream name partition' do
      it 'does not create stream name partition record' do
        expect { subject }.not_to change {
          PgEventstore.connection.with do |c|
            c.exec(
              'select * from partitions where context is not null and stream_name is not null and event_type is null'
            )
          end.to_a
        }
      end
      it 'does not create stream name partition table' do
        expect { subject }.not_to change {
          PgEventstore.connection.with do |c|
            c.exec("select * from pg_tables where tablename like 'stream_names_%'")
          end.to_a
        }
      end
    end

    shared_examples 'skips event type partition' do
      it 'does not create event type partition record' do
        expect { subject }.not_to change {
          PgEventstore.connection.with do |c|
            c.exec(<<~SQL)
              select * from partitions
                where context is not null and stream_name is not null and event_type is not null
            SQL
          end.to_a
        }
      end
      it 'does not create event type partition table' do
        expect { subject }.not_to change {
          PgEventstore.connection.with do |c|
            c.exec("select * from pg_tables where tablename like 'event_types_%'")
          end.to_a
        }
      end
    end

    context 'when no partitions exist' do
      it_behaves_like 'created context partition'
      it_behaves_like 'created stream name partition'
      it_behaves_like 'created event type partition'
    end

    context 'when context partition exists' do
      before do
        instance.create_context_partition(stream)
      end

      it_behaves_like 'skips context partition'
      it_behaves_like 'created stream name partition'
      it_behaves_like 'created event type partition'
    end

    context 'when stream name partition exists' do
      before do
        context_partition = instance.create_context_partition(stream)
        instance.create_stream_name_partition(stream, context_partition['table_name'])['table_name']
      end

      it_behaves_like 'skips context partition'
      it_behaves_like 'skips stream name partition'
      it_behaves_like 'created event type partition'
    end

    context 'when related event type partition exists' do
      before do
        context_partition = instance.create_context_partition(stream)
        stream_name_partition_name =
          instance.create_stream_name_partition(stream, context_partition['table_name'])['table_name']
        instance.create_event_type_partition(stream, event_type, stream_name_partition_name)
      end

      it_behaves_like 'skips context partition'
      it_behaves_like 'skips stream name partition'
      it_behaves_like 'skips event type partition'
    end
  end

  describe '#context_partition' do
    subject { instance.context_partition(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }

    context 'when context partition exists' do
      let!(:context_partition) { instance.create_context_partition(stream) }

      it 'returns it' do
        is_expected.to(
          eq(
            'id' => context_partition['id'], 'context' => 'SomeCtx', 'stream_name' => nil, 'event_type' => nil,
            'table_name' => 'contexts_81820a'
          )
        )
      end
    end

    context 'when context partition does not exist' do
      it { is_expected.to eq(nil) }
    end
  end

  describe '#stream_name_partition' do
    subject { instance.stream_name_partition(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }

    context 'when stream name partition exists' do
      let!(:stream_name_partition) do
        context_partition = instance.create_context_partition(stream)
        instance.create_stream_name_partition(stream, context_partition['table_name'])
      end

      it 'returns it' do
        is_expected.to(
          eq(
            'id' => stream_name_partition['id'], 'context' => 'SomeCtx', 'stream_name' => 'SomeStream',
            'event_type' => nil, 'table_name' => 'stream_names_ecb803'
          )
        )
      end
    end

    context 'when stream name partition does not exist' do
      it { is_expected.to eq(nil) }
    end
  end

  describe '#event_type_partition' do
    subject { instance.event_type_partition(stream, event_type) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }
    let(:event_type) { 'SomethingChanged' }

    context 'when event type partition exists' do
      let!(:event_type_partition) do
        context_partition = instance.create_context_partition(stream)
        stream_name_partition = instance.create_stream_name_partition(stream, context_partition['table_name'])
        instance.create_event_type_partition(stream, event_type, stream_name_partition['table_name'])
      end

      it 'returns it' do
        is_expected.to(
          eq(
            'id' => event_type_partition['id'], 'context' => 'SomeCtx', 'stream_name' => 'SomeStream',
            'event_type' => 'SomethingChanged', 'table_name' => 'event_types_aeadd5'
          )
        )
      end
    end

    context 'when event type partition does not exist' do
      it { is_expected.to eq(nil) }
    end
  end

  describe '#partition_name_taken?' do
    subject { instance.partition_name_taken?(name) }

    let(:name) { 'contexts_81820a' }

    context 'when partition table name is not taken yet' do
      it { is_expected.to eq(false) }
    end

    context 'when partition table name is taken already' do
      let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1') }

      before do
        instance.create_context_partition(stream)
      end

      it { is_expected.to eq(true) }
    end
  end

  describe '#find_by_ids' do
    subject { instance.find_by_ids([partition1['id'], partition2['id']]) }

    let(:partition1) { instance.create_context_partition(stream) }
    let(:partition2) { instance.create_stream_name_partition(stream, partition1['table_name']) }
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    it 'returns partitions by ids' do
      is_expected.to match_array([partition1, partition2])
    end
  end

  describe '#partitions' do
    subject { instance.partitions(stream_filters, event_filters) }

    let(:stream_filters) { [] }
    let(:event_filters) { [] }

    context 'when stream and event filters are empty' do
      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(type: 'Bar') }
      let(:event3) { PgEventstore::Event.new(type: 'Baz') }

      before do
        PgEventstore.client.append_to_stream(stream1, event1)
        PgEventstore.client.append_to_stream(stream2, event2)
        PgEventstore.client.append_to_stream(stream2, event3)
      end

      it 'returns every existing partition' do
        aggregate_failures do
          expect(subject.size).to eq(3)
          is_expected.to all be_a(PgEventstore::Partition)
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Foo', event_type: 'Foo')
          )
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Bar', event_type: 'Bar')
          )
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Bar', event_type: 'Baz')
          )
        end
      end
    end

    context 'when the given events appear in a certain stream' do
      let(:stream_filters) { [{ context: 'FooCtx', stream_name: 'Foo' }] }
      let(:event_filters) { ['Foo'] }

      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let!(:event) do
        event = PgEventstore::Event.new(type: 'Foo')
        PgEventstore.client.append_to_stream(stream, event)
      end

      it 'returns a partition holding that event type' do
        aggregate_failures do
          expect(subject.size).to eq(1)
          is_expected.to all be_a(PgEventstore::Partition)
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Foo', event_type: 'Foo')
          )
        end
      end
    end

    context 'when same event type appear in different streams' do
      let(:stream_filters) { [{ context: 'FooCtx', stream_name: 'Foo' }, { context: 'FooCtx', stream_name: 'Bar' }] }
      let(:event_filters) { ['Foo'] }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event) { PgEventstore::Event.new(type: 'Foo') }

      before do
        PgEventstore.client.append_to_stream(stream1, event)
        PgEventstore.client.append_to_stream(stream2, event)
      end

      it 'returns 2 different partitions with the given event filters, but different context/stream name combination' do
        aggregate_failures do
          expect(subject.size).to eq(2)
          is_expected.to all be_a(PgEventstore::Partition)
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Foo', event_type: 'Foo')
          )
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Bar', event_type: 'Foo')
          )
        end
      end
    end

    context 'when stream filters include only one stream' do
      let(:stream_filters) { [{ context: 'FooCtx', stream_name: 'Bar' }] }
      let(:event_filters) { ['Foo'] }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event) { PgEventstore::Event.new(type: 'Foo') }

      before do
        PgEventstore.client.append_to_stream(stream1, event)
        PgEventstore.client.append_to_stream(stream2, event)
      end

      it 'returns a partition of a combination of context/stream name of that filter' do
        aggregate_failures do
          expect(subject.size).to eq(1)
          is_expected.to all be_a(PgEventstore::Partition)
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Bar', event_type: 'Foo')
          )
        end
      end
    end

    context 'when event type in filter does not exist' do
      let(:stream_filters) { [{ context: 'FooCtx', stream_name: 'Foo' }, { context: 'FooCtx', stream_name: 'Bar' }] }
      let(:event_filters) { ['Fuu'] }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event) { PgEventstore::Event.new(type: 'Foo') }

      before do
        PgEventstore.client.append_to_stream(stream1, event)
        PgEventstore.client.append_to_stream(stream2, event)
      end

      it { is_expected.to eq([]) }
    end

    context 'when streams filter is empty' do
      let(:stream_filters) { [] }
      let(:event_filters) { %w[Foo Bar] }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Baz', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(type: 'Bar') }
      let(:event3) { PgEventstore::Event.new(type: 'BaZ') }

      before do
        PgEventstore.client.append_to_stream(stream1, event1)
        PgEventstore.client.append_to_stream(stream2, event2)
        PgEventstore.client.append_to_stream(stream3, event3)
      end

      it 'returns all partitions by the given events filter' do
        aggregate_failures do
          expect(subject.size).to eq(2)
          is_expected.to all be_a(PgEventstore::Partition)
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Foo', event_type: 'Foo')
          )
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Bar', event_type: 'Bar')
          )
        end
      end
    end

    context 'when events filter is empty' do
      let(:stream_filters) { [{ context: 'FooCtx', stream_name: 'Foo' }, { context: 'FooCtx', stream_name: 'Bar' }] }
      let(:event_filters) { [] }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Baz', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(type: 'Bar') }

      before do
        PgEventstore.client.append_to_stream(stream1, event1)
        PgEventstore.client.append_to_stream(stream2, event1)
        PgEventstore.client.append_to_stream(stream3, event2)
      end

      it 'returns all partitions by the given streams filter' do
        aggregate_failures do
          expect(subject.size).to eq(2)
          is_expected.to all be_a(PgEventstore::Partition)
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Foo', event_type: 'Foo')
          )
          expect(subject.map(&:options_hash)).to(
            include a_hash_including(context: 'FooCtx', stream_name: 'Bar', event_type: 'Foo')
          )
        end
      end
    end
  end

  describe '#context_partition_name' do
    subject { instance.context_partition_name(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'SomeStream', stream_id: '1') }

    it 'generates unique contexts table name' do
      is_expected.to eq('contexts_f3b092')
    end
  end

  describe '#stream_name_partition_name' do
    subject { instance.stream_name_partition_name(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyStream', stream_id: '1') }

    it 'generates unique stream_names table name' do
      is_expected.to eq('stream_names_272e88')
    end
  end

  describe '#event_type_partition_name' do
    subject { instance.event_type_partition_name(stream, event_type) }

    let(:stream) { PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyStream', stream_id: '1') }
    let(:event_type) { 'MyAwesomeEvent' }

    it 'generates unique event_types table name' do
      is_expected.to eq('event_types_bad91c')
    end
  end
end
