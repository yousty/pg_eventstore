# frozen_string_literal: true

RSpec.shared_examples 'resolves event class when reading from stream' do
  subject { instance.call(stream, options: options) }

  let(:event_class) { Class.new(PgEventstore::Event) }
  let(:event) { event_class.new }
  let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
  let(:options) { {} }

  before do
    stub_const('DummyClass', event_class)
    PgEventstore.client.append_to_stream(stream, event)
  end

  it "recognizes event's class" do
    expect(subject.first).to be_a(DummyClass)
  end

  context 'when :resolve_link_tos option is given' do
    let(:options) { { resolve_link_tos: true } }

    it "recognizes event's class" do
      expect(subject.first).to be_a(DummyClass)
    end
  end
end
