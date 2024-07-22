# frozen_string_literal: true

RSpec.describe PgEventstore::EventSerializer do
  let(:instance) { described_class.new(middlewares) }
  let(:middlewares) { [] }

  describe '#serialize' do
    subject { instance.serialize(event) }

    let(:event) { PgEventstore::Event.new(type: 'foo') }

    context 'when no middlewares are given' do
      it 'returns an event as is' do
        expect { subject }.not_to change { event }
      end
    end

    context 'when middlewares are given' do
      let(:middlewares) { [DummyMiddleware.new, another_middleware.new] }
      let(:another_middleware) do
        Class.new do
          include PgEventstore::Middleware

          def serialize(event)
            event.metadata['foo'] = 'bar'
          end
        end
      end

      it 'passes the given event through all middlewares' do
        expect { subject }.to change { event.metadata }.to('dummy_secret' => DummyMiddleware::ENCR_SECRET, 'foo' => 'bar')
      end
    end
  end

  describe '#without_middlewares' do
    subject { instance.without_middlewares }

    let(:middlewares) { [DummyMiddleware.new] }

    it 'returns new instance without middlewares' do
      aggregate_failures do
        is_expected.to be_a(described_class)
        expect(subject.middlewares).to be_empty
      end
    end
  end
end
