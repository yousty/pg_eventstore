# frozen_string_literal: true

RSpec.describe PgEventstore::Chunks::SubscriptionEventsIndexChunk do
  let(:event_subscription_position_queries) { PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection) }

  describe '#take' do
    subject { instance.take(size) }

    let(:instance) do
      described_class.new(
        indexes,
        PgEventstore.connection,
        PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection),
        resolve_link_tos
      )
    end
    let(:indexes) { [] }
    let(:resolve_link_tos) { false }
    let(:size) { nil }

    context 'when indexes are empty' do
      it { is_expected.to eq([]) }
    end

    context 'when indexes are present' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:event1) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo'))
      end
      let(:event2) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Bar'))
      end
      let(:indexes) { prepare_subscription_indexes([event1, event2]) }

      before do
        reset_events_subscription_position
      end

      context 'when size is nil' do
        it 'returns all events' do
          expect(subject.map(&:options_hash)).to(
            match(
              [
                { attributes: a_hash_including('id' => event1.id), subscription_position: 1 },
                { attributes: a_hash_including('id' => event2.id), subscription_position: 2 },
              ]
            )
          )
        end
        it 'returns empty array on subsequent calls' do
          instance.take(size)
          is_expected.to eq([])
        end
      end

      context 'when size is a number' do
        let(:size) { 1 }

        it 'returns exactly that number of events' do
          expect(subject.map(&:options_hash)).to(
            match(
              [
                { attributes: a_hash_including('id' => event1.id), subscription_position: 1 },
              ]
            )
          )
        end
        it 'drains the chunk on subsequent calls' do
          aggregate_failures do
            expect(instance.take(size).map(&:options_hash)).to(
              match([{ attributes: a_hash_including('id' => event1.id), subscription_position: 1 }])
            )
            expect(instance.take(size).map(&:options_hash)).to(
              match([{ attributes: a_hash_including('id' => event2.id), subscription_position: 2 }])
            )
            is_expected.to eq([])
          end
        end
      end
    end

    context 'when some events behind indexes are link events' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:event1) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo'))
      end
      let(:event2) do
        PgEventstore.client.link_to(stream, event1)
      end
      let(:indexes) { prepare_subscription_indexes([event1, event2]) }

      before do
        reset_events_subscription_position
      end

      context 'when resolve_link_tos is false' do
        it 'returns raw events as is' do
          expect(subject.map(&:options_hash)).to(
            match(
              [
                { attributes: a_hash_including('id' => event1.id), subscription_position: 1 },
                { attributes: a_hash_including('id' => event2.id), subscription_position: 2 },
              ]
            )
          )
        end
      end

      context 'when resolve_link_tos is true' do
        let(:resolve_link_tos) { true }

        it 'returns raw events as is' do
          expect(subject.map(&:options_hash)).to(
            match(
              [
                { attributes: a_hash_including('id' => event1.id), subscription_position: 1 },
                { attributes: a_hash_including('id' => event1.id), subscription_position: 2 },
              ]
            )
          )
        end
      end
    end

    context 'when global_position order does not correspond to subscription_position order' do
      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2') }
      let(:event1) do
        PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'Foo'))
      end
      let(:event2) do
        PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'Bar'))
      end
      let(:indexes) { prepare_subscription_indexes([event1, event2]) }

      before do
        reset_events_subscription_position
        event1
        event2
        event_subscription_position_queries.assign_subscription_position
        PgEventstore.connection.with do |conn|
          conn.exec_params(
            'update events set global_position = 0 where global_position = $1', [event2.global_position]
          )
          conn.exec_params(
            'update events_global_index set global_position = 0 where global_position = $1', [event2.global_position]
          )
          conn.exec_params(
            'update event_subscription_positions set global_position = 0 where global_position = $1',
            [event2.global_position]
          )
        end
        event2.global_position = 0
      end

      it 'returns raw events in the correct order' do
        expect(subject.map { [_1.attributes['id'], _1.subscription_position] }).to(
          eq(
            [
              [event1.id, 1],
              [event2.id, 2],
            ]
          )
        )
      end
    end
  end

  describe '#drained?' do
    subject { instance.drained? }

    let(:instance) do
      described_class.new(
        indexes,
        PgEventstore.connection,
        PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection),
        false
      )
    end
    let(:indexes) { [] }

    context 'when indexes are empty' do
      it { is_expected.to eq(true) }
    end

    context 'when indexes are present' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:event1) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo'))
      end
      let(:event2) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Bar'))
      end
      let(:indexes) { prepare_subscription_indexes([event1, event2]) }

      before do
        reset_events_subscription_position
      end

      context 'when indexes are not resolved all in once' do
        before do
          stub_const("#{described_class}::MAX_PARTITIONS_TO_RESOLVE_PER_CALL", 1)
          instance.take(1)
        end

        it { is_expected.to eq(false) }
      end

      context 'when indexes are resolved all in once' do
        before do
          instance.take(1)
        end

        it { is_expected.to eq(false) }
      end

      context 'when chunk is drained' do
        before do
          instance.take(2)
        end

        it { is_expected.to eq(true) }
      end
    end
  end

  describe '#size' do
    subject { instance.size }

    let(:instance) do
      described_class.new(
        indexes,
        PgEventstore.connection,
        PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection),
        false
      )
    end
    let(:indexes) { [] }

    context 'when indexes are empty' do
      it { is_expected.to eq(0) }
    end

    context 'when indexes are present' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:event1) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo'))
      end
      let(:event2) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Bar'))
      end
      let(:indexes) { prepare_subscription_indexes([event1, event2]) }

      before do
        reset_events_subscription_position
      end

      context 'when indexes are not resolved all in once' do
        before do
          stub_const("#{described_class}::MAX_PARTITIONS_TO_RESOLVE_PER_CALL", 1)
          instance.take(1)
        end

        it { is_expected.to eq(1) }
      end

      context 'when indexes are resolved all in once' do
        before do
          instance.take(1)
        end

        it { is_expected.to eq(1) }
      end

      context 'when chunk is drained' do
        before do
          instance.take(2)
        end

        it { is_expected.to eq(0) }
      end
    end
  end

  describe '#last' do
    subject { instance.last }

    let(:instance) do
      described_class.new(
        indexes,
        PgEventstore.connection,
        PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection),
        false
      )
    end
    let(:indexes) { [] }

    context 'when indexes are empty' do
      it { is_expected.to eq(nil) }
    end

    context 'when indexes are present' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:event1) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo'))
      end
      let(:event2) do
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Bar'))
      end
      let(:indexes) { prepare_subscription_indexes([event1, event2]) }

      before do
        reset_events_subscription_position
      end

      it 'returns last index' do
        is_expected.to eq(indexes.last)
      end
    end
  end

  describe 'resolving indexes' do
    subject { instance.send(:resolve_indexes) }

    let(:instance) do
      described_class.new(
        indexes,
        PgEventstore.connection,
        PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection),
        false
      )
    end
    let(:indexes) { [] }
    let(:max_partitions_to_resolve) { 10 }

    before do
      stub_const("#{described_class}::MAX_PARTITIONS_TO_RESOLVE_PER_CALL", max_partitions_to_resolve)
    end

    context 'when number of unique event types is greater that MAX_PARTITIONS_TO_RESOLVE_PER_CALL' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:events) do
        PgEventstore.client.append_to_stream(
          stream,
          Array.new(max_partitions_to_resolve + 1) { PgEventstore::Event.new(type: "Foo-#{_1}") }
        )
      end
      let(:indexes) { prepare_subscription_indexes(events) }

      before do
        reset_events_subscription_position
      end

      it 'resolves first MAX_PARTITIONS_TO_RESOLVE_PER_CALL indexes' do
        expect { subject }.to change {
          instance.instance_variable_get(:@raw_events).map { _1.attributes['id'] }
        }.to(events.first(max_partitions_to_resolve).map(&:id))
      end
      it 'keeps the rest of indexes unresolved' do
        expect { subject }.to change { instance.instance_variable_get(:@indexes) }.to([indexes.last])
      end
      it 'does not mark instance as resolved' do
        expect { subject }.not_to change { instance.send(:resolved?) }
      end
    end

    context 'when number of unique event types within the limit is spread across the whole chunk' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
      let(:events) do
        PgEventstore.client.append_to_stream(
          stream,
          Array.new(max_partitions_to_resolve) { [PgEventstore::Event.new(type: "Foo-#{_1}")] * 2 }.flatten
        )
      end
      let(:indexes) { prepare_subscription_indexes(events) }

      before do
        reset_events_subscription_position
      end

      it 'resolves all indexes at once' do
        expect { subject }.to change {
          instance.instance_variable_get(:@raw_events).map { _1.attributes['id'] }
        }.to(events.map(&:id))
      end
      it 'does not keep any unresolved indexes' do
        expect { subject }.to change { instance.instance_variable_get(:@indexes) }.to([])
      end
      it 'marks instance as resolved' do
        expect { subject }.to change { instance.send(:resolved?) }.to(true)
      end
    end
  end
end
