# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::Multiple do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(transactions: transaction_queries)
  end
  let(:transaction_queries) { PgEventstore::TransactionQueries.new(PgEventstore.connection) }

  describe '#call' do
    subject { instance.call(read_only: read_only) { commands } }

    let(:read_only) { false }
    let(:commands) { PgEventstore.client.read(PgEventstore::Stream.all_stream) }

    context 'when performing mutating commands' do
      let(:commands) do
        PgEventstore.client.append_to_stream(events_stream1, event1)
        PgEventstore.client.append_to_stream(events_stream1, event2)
        PgEventstore.client.append_to_stream(events_stream2, [event3, event4])
      end

      let(:events_stream1) do
        PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
      end
      let(:events_stream2) do
        PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: '1234')
      end
      let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
      let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
      let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }
      let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }

      context 'when transaction is read-write' do
        it 'appends given events' do
          subject
          expect(PgEventstore.client.read(PgEventstore::Stream.all_stream).map(&:id)).to(
            eq([event1.id, event2.id, event3.id, event4.id])
          )
        end
      end

      context 'when transaction is read-only' do
        let(:read_only) { true }

        it 'raises error' do
          expect { subject }.to raise_error(PG::ReadOnlySqlTransaction)
        end
      end
    end

    context 'when performing read-only commands' do
      context 'when transaction is read-write' do
        it 'returns its result' do
          is_expected.to eq([])
        end
      end

      context 'when transaction is read-only' do
        let(:read_only) { true }

        it 'returns its result' do
          is_expected.to eq([])
        end
      end
    end
  end

  describe 'multiple commands consistency' do
    let(:event1) { PgEventstore::Event.new(type: 'foo', data: { event: 'event-1' }) }
    let(:event2) { PgEventstore::Event.new(type: 'bar', data: { event: 'event-2' }) }
    let(:event3) { PgEventstore::Event.new(type: 'baz', data: { event: 'event-3' }) }
    let(:event4) { PgEventstore::Event.new(type: 'baz', data: { event: 'event-4' }) }
    let(:event5) { PgEventstore::Event.new(type: 'bar', data: { event: 'event-5' }) }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: 'stream-1')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: 'stream-2')
    end
    let(:events_stream3) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream1', stream_id: 'stream-3')
    end
    let(:pattern1) do
      [
        { stream: events_stream1, event: event1 }, { stream: events_stream1, event: event3 },
        { stream: events_stream3, event: event2 }, { stream: events_stream3, event: event4 }
      ]
    end
    let(:pattern2) do
      [
        { stream: events_stream2, event: event1 },
        { stream: events_stream3, event: event2 }, { stream: events_stream3, event: event5 }
      ]
    end
    let(:pattern3) do
      [
        { stream: events_stream3, event: event5 },
        { stream: events_stream1, event: event1 }, { stream: events_stream1, event: event5 }
      ]
    end
    let(:patterns) { { 'pattern1' => pattern1, 'pattern2' => pattern2, 'pattern3' => pattern3 } }
    let(:iterations_number) { 3 }

    # rubocop:disable RSpec/MultipleExpectations
    it 'checks it' do
      iterations_number.times.flat_map do |i|
        patterns.values.map do |pattern|
          Thread.new do
            sleep 0.1 + (i / 10.0)
            instance.call(read_only: false) do
              pattern.group_by { |h| h[:stream] }.each do |stream, attrs|
                PgEventstore.client.append_to_stream(stream, attrs.map { |h| h[:event] })
              end
            end
          end
        end
      end.each(&:join)

      [events_stream1, events_stream2, events_stream3].each do |stream|
        events = PgEventstore.client.read(stream)
        grouped_events = [pattern1, pattern2, pattern3].flatten.group_by { |h| h[:stream] }
        events_count = grouped_events[stream].size * iterations_number
        expect(events.map(&:stream_revision)).to(
          eq((0...events_count).to_a), "Stream #{stream.inspect} has incorrect revisions sequence!"
        )
      end

      # Check patterns sequences. Multiple command must be atomic. Events, created inside Multiple command must go in
      # the unbreakable order. If anything from the bellow fails - it means the implementation is broken
      events = PgEventstore.client.read(PgEventstore::Stream.all_stream)
      position = 0

      human_readable_sequence = events.map { |e| [e.stream.stream_id, e.data['event']] }
      while position < events.size
        # Detect the pattern by the event at the given position. If you ever modify patterns definitions - make sure
        # they all have uniq combination of event and stream at index 0.
        pattern_name, pattern = patterns.find do |_name, info|
          events[position].stream == info.first[:stream] &&
            events[position].data['event'] == info.first[:event].data[:event]
        end

        unless pattern
          expect(true).to eq(false), "Sequence #{human_readable_sequence} at position #{position} is not recognizable."
        end

        events[position...(position + pattern.size)].each.with_index do |event, index|
          human_readable_events = events[position...(position + pattern.size)].map do |e|
            [e.stream.stream_id, e.data['event']]
          end
          error_message = "Expected to see #{pattern_name} at position #{position}, but got #{human_readable_events}."
          expect({ stream: event.stream.stream_id, event: event.data['event'] }).to(
            eq({ stream: pattern[index][:stream].stream_id, event: pattern[index][:event].data[:event] }),
            error_message
          )
        end
        position += pattern.size
      end
    end
    # rubocop:enable RSpec/MultipleExpectations
  end
end
