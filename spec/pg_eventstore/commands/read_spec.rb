# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::Read do
  let(:instance) { described_class.new(PgEventstore.connection, middlewares, event_class_resolver) }
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#call' do
    subject { instance.call(stream, options: options) }

    let(:options) { {} }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyAwesomeStream', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'MyAwesomeStream', stream_id: '1234')
    end
    let(:stream) { events_stream1 }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :baz) }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :baz) }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event2, event3])
      PgEventstore.client.append_to_stream(events_stream2, event4)
    end

    context 'when no options are given' do
      it 'returns events' do
        expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
      end
    end

    context 'when :direction option is given' do
      context 'when value of it is "Backwards"' do
        let(:options) { { direction: 'Backwards' } }

        it 'returns events in descending order' do
          expect(subject.map(&:id)).to eq([event3.id, event2.id, event1.id])
        end
      end

      context 'when value of it is "Forwards"' do
        let(:options) { { direction: 'Forwards' } }

        it 'returns events in ascending order' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
        end
      end

      context 'when value of it is something else' do
        let(:options) { { direction: 'some unhandled direction value' } }

        it 'returns events in ascending order' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
        end
      end
    end

    context 'when :from_revision option is given' do
      let(:options) { { from_revision: 1 } }

      context 'when reading from regular stream' do
        it 'returns events, starting from the given stream revision' do
          expect(subject.map(&:id)).to eq([event2.id, event3.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id, event4.id])
        end
      end
    end

    context 'when :from_position option is given' do
      let(:options) { { from_position: PgEventstore.client.read(events_stream1).last(2).first.global_position } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns events, starting from the given global position' do
          expect(subject.map(&:id)).to eq([event2.id, event3.id, event4.id])
        end
      end
    end

    context 'when :max_count option is given' do
      let(:options) { { max_count: 2 } }

      it 'limits number of the events in the result' do
        expect(subject.map(&:id)).to eq([event1.id, event2.id])
      end
    end

    context 'when :resolve_link_tos option is given' do
      let(:options) { { resolve_link_tos: true } }



    end

    describe 'links' do
      let(:existing_event) { PgEventstore.client.read(events_stream2).first }
      let!(:link) do
        # TODO: use LinkTo command here when it will be implemented instead manual query
        instance.send(:queries).insert(
          PgEventstore::Event.new(link_id: existing_event.global_position, stream_revision: 1, **existing_event.stream)
        )
      end
      let(:stream) { events_stream2 }

      context 'when :resolve_link_tos is not provided' do
        it 'returns links as is' do
          expect(subject.map(&:id)).to eq([existing_event.id, link.id])
        end
      end

      context 'when :resolve_link_tos is provided' do
        let(:options) { { resolve_link_tos: true } }

        it 'resolves links to original events' do
          expect(subject.map(&:id)).to eq([existing_event.id, existing_event.id])
        end
      end
    end

    describe 'reading last event in the regular stream' do
      let(:options) { { max_count: 1, direction: 'Backwards' } }

      it 'returns last event of the stream' do
        expect(subject.map(&:id)).to eq([event3.id])
      end
    end

    describe 'reading last event in "all" stream' do
      let(:stream) { PgEventstore::Stream.all_stream }
      let(:options) { { max_count: 1, direction: 'Backwards' } }

      it 'returns last event of the stream' do
        expect(subject.map(&:id)).to eq([event4.id])
      end
    end
  end
end
