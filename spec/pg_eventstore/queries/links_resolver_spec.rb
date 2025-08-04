# frozen_string_literal: true

RSpec.describe PgEventstore::LinksResolver do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#resolve' do
    subject { instance.resolve(raw_events) }

    let(:stream) { PgEventstore::Stream.new(context: 'MyCtx', stream_name: 'MyStream', stream_id: '1') }
    let(:event1) do
      event = PgEventstore::Event.new(data: { foo: :bar })
      PgEventstore.client.append_to_stream(stream, event)
    end
    let(:event2) do
      event = PgEventstore::Event.new(data: { bar: :baz })
      PgEventstore.client.append_to_stream(stream, event)
    end
    let(:link) do
      PgEventstore.client.link_to(stream, event1)
    end

    let(:raw_event1) do
      PgEventstore.connection.with do |c|
        c.exec_params('select * from events where id = $1', [event1.id])
      end.to_a.first
    end
    let(:raw_event2) do
      PgEventstore.connection.with do |c|
        c.exec_params('select * from events where id = $1', [event2.id])
      end.to_a.first
    end
    let(:raw_link) do
      PgEventstore.connection.with do |c|
        c.exec_params('select *, 123 as runner_id from events where id = $1', [link.id])
      end.to_a.first
    end

    let(:raw_events) { [raw_event1, raw_link, raw_event2] }

    it 'resolves link events to original events' do
      is_expected.to(
        eq(
          [
            raw_event1,
            raw_event1.merge('runner_id' => 123, 'link' => raw_link),
            raw_event2,
          ]
        )
      )
    end

    context 'when no link events are given' do
      let(:raw_events) { [raw_event1, raw_event2] }

      it 'returns raw events as is' do
        is_expected.to eq(raw_events)
      end
    end
  end
end
