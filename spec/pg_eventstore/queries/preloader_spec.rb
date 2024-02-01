# frozen_string_literal: true

RSpec.describe PgEventstore::Preloader do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#preload_related_objects' do
    subject { instance.preload_related_objects(raw_events) }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2') }
    let!(:event1) { PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'Foo')) }
    let!(:event2) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'Bar')) }

    let(:raw_events) { PgEventstore.connection.with { |c| c.exec('select * from events') }.to_a }

    it 'preloads streams and event types for the given raw events' do
      is_expected.to(
        match(
          [
            a_hash_including(
              'id' => event1.id, 'type' => 'Foo',
              'stream' => {
                'id' => event1.stream.id,
                'context' => stream1.context,
                'stream_name' => stream1.stream_name,
                'stream_id' => '1',
                'stream_revision' => 0
              }
            ),
            a_hash_including(
              'id' => event2.id,
              'type' => 'Bar',
              'stream' => {
                'id' => event2.stream.id,
                'context' => stream2.context,
                'stream_name' => stream2.stream_name,
                'stream_id' => '2',
                'stream_revision' => 0
              }
            ),
          ]
        )
      )
    end
  end
end
