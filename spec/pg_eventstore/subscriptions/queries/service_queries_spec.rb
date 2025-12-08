# frozen_string_literal: true

RSpec.describe PgEventstore::ServiceQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#relation_transaction_ids' do
    subject { instance.relation_transaction_ids(relation_oids) }

    let(:relation_oids) { [] }

    context 'when empty array is provided' do
      it { is_expected.to eq([]) }
    end

    context 'when non-existing oids are provided' do
      let(:relation_oids) { [1] }

      it { is_expected.to eq([]) }
    end

    context 'when existing oids are provided' do
      let(:relation_oids) { [instance.relation_ids_by_names(['events'])['events']] }

      context 'when there are no running transactions for the given oids' do
        it { is_expected.to eq([]) }
      end

      context 'when there are running transactions for the given oids' do
        let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
        let(:event) { PgEventstore::Event.new(type: 'Foo') }

        before do
          @publisher = Thread.new do
            PgEventstore.client.multiple do
              PgEventstore.client.append_to_stream(stream, event)
              loop do
                break if Thread.current[:exit]

                sleep 0.01
              end
            end
          end
          # Let the thread time to start
          sleep 0.1
        end

        after do
          @publisher[:exit] = true
          @publisher.join
        end

        it 'returns currently running transaction ids' do
          is_expected.to match([kind_of(String)])
        end
      end
    end
  end

  describe '#transactions_in_progress?' do
    subject { instance.transactions_in_progress?(relation_ids: relation_ids, transaction_ids: transaction_ids) }

    let(:relation_ids) { [] }
    let(:transaction_ids) { [] }

    context 'when ids are empty' do
      it { is_expected.to eq(false) }
    end

    context 'when non-existing ids are provided' do
      let(:relation_ids) { [1] }
      let(:transaction_ids) { ['2'] }

      it { is_expected.to eq(false) }
    end

    context 'when existing ids are provided' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:event) { PgEventstore::Event.new(type: 'Foo') }

      let(:relation_ids) { [instance.relation_ids_by_names(['events'])['events']] }
      let(:transaction_ids) { instance.relation_transaction_ids(relation_ids) }

      before do
        @publisher = Thread.new do
          PgEventstore.client.multiple do
            PgEventstore.client.append_to_stream(stream, event)
            loop do
              break if Thread.current[:exit]

              sleep 0.01
            end
          end
        end
        # Let the thread time to start
        sleep 0.1
      end

      after do
        @publisher[:exit] = true
        @publisher.join
      end

      context 'when transaction is running' do
        it { is_expected.to eq(true) }
      end

      context 'when transaction is no longer running' do
        before do
          @publisher[:exit] = true
          @publisher.join
        end

        it { is_expected.to eq(false) }
      end
    end
  end

  describe '#max_global_position' do
    subject { instance.max_global_position(table_names) }

    let(:table_names) { [] }

    context 'when table names are absent' do
      it { is_expected.to eq(0) }
    end

    context 'when table names are present' do
      let(:table_names) do
        [
          partition_queries.event_type_partition_name(stream2, event2.type),
          partition_queries.context_partition_name(stream1),
        ]
      end

      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }
      let(:stream3) { PgEventstore::Stream.new(context: 'BazCtx', stream_name: 'Baz', stream_id: '1') }

      let(:event1) do
        PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'Foo'))
      end
      let(:event2) do
        PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'Foo'))
      end
      let(:event3) do
        PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new(type: 'Foo'))
      end

      before do
        event1
        event2
        event3
      end

      it 'returns max global_position among provided tables' do
        is_expected.to eq(event2.global_position)
      end
    end
  end

  describe '#relation_ids_by_names' do
    subject { instance.relation_ids_by_names(table_names) }

    let(:table_names) { [] }

    context 'when table names are absent' do
      it { is_expected.to eq({}) }
    end

    context 'when non-existing table names are provided' do
      let(:table_names) { ['events1'] }

      it { is_expected.to eq({}) }
    end

    context 'when existing table names are provided' do
      let(:table_names) do
        [
          partition_queries.context_partition_name(stream),
          partition_queries.stream_name_partition_name(stream),
          partition_queries.event_type_partition_name(stream, event.type),
          'events',
        ]
      end

      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:event) { PgEventstore::Event.new(type: 'Foo') }

      before do
        PgEventstore.client.append_to_stream(stream, event)
      end

      it 'returns table_name-to-oid association' do
        is_expected.to(
          match(
            partition_queries.context_partition_name(stream) => kind_of(Integer),
            partition_queries.stream_name_partition_name(stream) => kind_of(Integer),
            partition_queries.event_type_partition_name(stream, event.type) => kind_of(Integer),
            'events' => kind_of(Integer)
          )
        )
      end
    end
  end
end
