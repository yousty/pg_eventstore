# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Application, type: :request do
  let(:app) { described_class }

  describe 'GET /' do
    subject { get '/', params }

    let(:params) { {} }

    let!(:events1) do
      events = [PgEventstore::Event.new(type: "Foo")] * 5
      PgEventstore.client.append_to_stream(stream1, events)
    end
    let!(:events2) do
      events = [PgEventstore::Event.new(type: "Bar")] * 6
      PgEventstore.client.append_to_stream(stream2, events)
    end
    let(:events) { events1 + events2 }
    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

    it 'displays last 10 events' do
      subject
      aggregate_failures do
        expect(rendered_event_ids).to eq(events[1..10].map(&:id).reverse)
        expect(rendered_event_ids).not_to include(events.first.id)
      end
    end

    context 'when events limit is set to 20' do
      let(:params) { { per_page: 20 } }

      it 'displays up to 100 events' do
        subject
        expect(rendered_event_ids).to eq(events.map(&:id).reverse)
      end
    end

    context 'when starting_id is provided' do
      let(:params) { { starting_id: events.first.global_position } }

      it 'displays events from the given id' do
        subject
        expect(rendered_event_ids).to eq([events.first.id])
      end
    end

    context 'when order is provided' do
      let(:params) { { order: :asc } }

      it 'displays first 10 events' do
        subject
        aggregate_failures do
          expect(rendered_event_ids).to eq(events[0..9].map(&:id))
          expect(rendered_event_ids).not_to include(events.last.id)
        end
      end
    end

    context 'when events filter is provided' do
      let(:params) { { filter: { events: ['Bar'] } } }

      it 'displays only filtered events' do
        subject
        expect(rendered_event_ids).to eq(events2.map(&:id).reverse)
      end
    end

    context 'when stream filter is provided' do
      let(:params) { { filter: { streams: [{ context: 'FooCtx', stream_name: 'Foo', stream_id: '' }] } } }

      it 'displays only filtered events' do
        subject
        expect(rendered_event_ids).to eq(events1.map(&:id).reverse)
      end
    end
  end

  describe 'POST /change_config' do
    subject { post '/change_config', params }

    let(:params) { { config: :some_config } }

    context 'when config is recognizable' do
      before do
        PgEventstore.configure(name: :some_config) do |config|
          config.max_count = 100
        end
      end

      after do
        PgEventstore.send(:init_variables)
      end

      it 'persists it in session' do
        subject
        expect(last_request.session[:current_config]).to eq(:some_config)
      end
    end

    context 'when config is not recognizable' do
      it 'sets it to :default' do
        subject
        expect(last_request.session[:current_config]).to eq(:default)
      end
    end
  end

  describe 'GET /stream_contexts_filtering' do
    subject { get '/stream_contexts_filtering', params }

    let(:params) { {} }

    let(:stream1) { PgEventstore::Stream.new(context: 'FacCtx', stream_name: 'MyStream', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FabCtx', stream_name: 'MyStream', stream_id: '1') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FbcCtx', stream_name: 'MyStream', stream_id: '1') }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new)
    end

    it 'returns all contexts' do
      subject
      expect(parsed_body).to(
        eq(
          'results' => [{ 'context' => 'FabCtx' }, { 'context' => 'FacCtx' }, { 'context' => 'FbcCtx' }],
          'pagination' => { 'more' => false, 'starting_id' => nil }
        )
      )
    end

    context 'when there are more results than in current response' do
      before do
        stub_const('PgEventstore::Paginator::StreamContextsCollection::PER_PAGE', 2)
      end

      it 'paginates it' do
        subject
        expect(parsed_body).to(
          eq(
            'results' => [{ 'context' => 'FabCtx' }, { 'context' => 'FacCtx' }],
            'pagination' => { 'more' => true, 'starting_id' => 'FbcCtx' }
          )
        )
      end
    end

    context 'when :starting_id param is provided' do
      let(:params) { { starting_id: 'FacCtx' } }

      it 'returns contexts starting from the provided one' do
        subject
        expect(parsed_body['results']).to eq([{ 'context' => 'FacCtx' }, { 'context' => 'FbcCtx' }])
      end
    end

    context 'when :term param is provided' do
      let(:params) { { term: 'Fa' } }

      it 'returns contexts which start from that value' do
        subject
        expect(parsed_body['results']).to eq([{ 'context' => 'FabCtx' }, { 'context' => 'FacCtx' }])
      end
    end
  end

  describe 'GET /stream_names_filtering' do
    subject { get '/stream_names_filtering', params }

    let(:params) { { context: 'FooCtx' } }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Fac', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Fab', stream_id: '1') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Fbc', stream_id: '1') }
    let(:stream4) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Fad', stream_id: '1') }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream4, PgEventstore::Event.new)
    end

    it 'returns stream names for the given context' do
      subject
      expect(parsed_body).to(
        eq(
          'results' => [{ 'stream_name' => 'Fab' }, { 'stream_name' => 'Fac' }, { 'stream_name' => 'Fbc' }],
          'pagination' => { 'more' => false, 'starting_id' => nil }
        )
      )
    end

    context 'when there are more results than in current response' do
      before do
        stub_const('PgEventstore::Paginator::StreamNamesCollection::PER_PAGE', 2)
      end

      it 'paginates it' do
        subject
        expect(parsed_body).to(
          eq(
            'results' => [{ 'stream_name' => 'Fab' }, { 'stream_name' => 'Fac' }],
            'pagination' => { 'more' => true, 'starting_id' => 'Fbc' }
          )
        )
      end
    end

    context 'when another context is provided' do
      let(:params) { { context: 'BarCtx' } }

      it 'returns stream names from that context' do
        subject
        expect(parsed_body['results']).to eq([{ 'stream_name' => 'Fad' }])
      end
    end

    context 'when non-existing context is provided' do
      let(:params) { { context: 'BazCtx' } }

      it 'returns no results' do
        subject
        expect(parsed_body['results']).to eq([])
      end
    end

    context 'when :starting_id param is provided' do
      let(:params) { super().merge(starting_id: 'Fac') }

      it 'returns stream names starting from the provided one' do
        subject
        expect(parsed_body['results']).to eq([{ 'stream_name' => 'Fac' }, { 'stream_name' => 'Fbc' }])
      end
    end

    context 'when :term param is provided' do
      let(:params) { super().merge(term: 'Fa') }

      it 'returns stream names which start from that value' do
        subject
        expect(parsed_body['results']).to eq([{ 'stream_name' => 'Fab' }, { 'stream_name' => 'Fac' }])
      end
    end
  end

  describe 'GET /stream_ids_filtering' do
    subject { get '/stream_ids_filtering', params }

    let(:params) { { context: 'FooCtx', stream_name: 'MyStream' } }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Fac') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Fab') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Fbc') }
    let(:stream4) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'AnotherStream', stream_id: 'Fad') }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream4, PgEventstore::Event.new)
    end

    it 'returns stream ids for the given context and stream_name' do
      subject
      expect(parsed_body).to(
        eq(
          'results' => [{ 'stream_id' => 'Fab' }, { 'stream_id' => 'Fac' }, { 'stream_id' => 'Fbc' }],
          'pagination' => { 'more' => false, 'starting_id' => nil }
        )
      )
    end

    context 'when there are more results than in current response' do
      before do
        stub_const('PgEventstore::Paginator::StreamIdsCollection::PER_PAGE', 2)
      end

      it 'paginates it' do
        subject
        expect(parsed_body).to(
          eq(
            'results' => [{ 'stream_id' => 'Fab' }, { 'stream_id' => 'Fac' }],
            'pagination' => { 'more' => true, 'starting_id' => 'Fbc' }
          )
        )
      end
    end

    context 'when another context and stream anem is provided' do
      let(:params) { { context: 'BarCtx', stream_name: 'AnotherStream' } }

      it 'returns stream ids from there' do
        subject
        expect(parsed_body['results']).to eq([{ 'stream_id' => 'Fad' }])
      end
    end

    context 'when non-existing stream name is provided' do
      let(:params) { { context: 'BarCtx', stream_name: 'MyStream' } }

      it 'returns no results' do
        subject
        expect(parsed_body['results']).to eq([])
      end
    end

    context 'when :starting_id param is provided' do
      let(:params) { super().merge(starting_id: 'Fac') }

      it 'returns stream ids starting from the provided one' do
        subject
        expect(parsed_body['results']).to eq([{ 'stream_id' => 'Fac' }, { 'stream_id' => 'Fbc' }])
      end
    end

    context 'when :term param is provided' do
      let(:params) { super().merge(term: 'Fa') }

      it 'returns stream ids which start from that value' do
        subject
        expect(parsed_body['results']).to eq([{ 'stream_id' => 'Fab' }, { 'stream_id' => 'Fac' }])
      end
    end
  end

  describe 'GET /event_types_filtering' do
    subject { get '/event_types_filtering', params }

    let(:params) { {} }

    let(:stream) { PgEventstore::Stream.new(context: 'FacCtx', stream_name: 'MyStream', stream_id: '1') }
    let(:event1) { PgEventstore::Event.new(type: 'Fac') }
    let(:event2) { PgEventstore::Event.new(type: 'Fab') }
    let(:event3) { PgEventstore::Event.new(type: 'Fbc') }

    before do
      PgEventstore.client.append_to_stream(stream, [event1, event2, event3])
    end

    it 'returns all event types' do
      subject
      expect(parsed_body).to(
        eq(
          'results' => [{ 'event_type' => 'Fab' }, { 'event_type' => 'Fac' }, { 'event_type' => 'Fbc' }],
          'pagination' => { 'more' => false, 'starting_id' => nil }
        )
      )
    end

    context 'when there are more results than in current response' do
      before do
        stub_const('PgEventstore::Paginator::EventTypesCollection::PER_PAGE', 2)
      end

      it 'paginates it' do
        subject
        expect(parsed_body).to(
          eq(
            'results' => [{ 'event_type' => 'Fab' }, { 'event_type' => 'Fac' }],
            'pagination' => { 'more' => true, 'starting_id' => 'Fbc' }
          )
        )
      end
    end

    context 'when :starting_id param is provided' do
      let(:params) { { starting_id: 'Fac' } }

      it 'returns event types starting from the provided one' do
        subject
        expect(parsed_body['results']).to eq([{ 'event_type' => 'Fac' }, { 'event_type' => 'Fbc' }])
      end
    end

    context 'when :term param is provided' do
      let(:params) { { term: 'Fa' } }

      it 'returns event types which start from that value' do
        subject
        expect(parsed_body['results']).to eq([{ 'event_type' => 'Fab' }, { 'event_type' => 'Fac' }])
      end
    end
  end
end
