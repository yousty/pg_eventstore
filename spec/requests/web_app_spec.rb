# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Application, type: :request do
  let(:app) { described_class }

  shared_examples 'admin web ui config' do
    before do
      # Make default config broken by setting available connections to zero to demonstrate the difference between it
      # and Admin UI config
      PgEventstore.configure do |config|
        config.connection_pool_size = 0
        config.connection_pool_timeout = 1
      end
    end

    after do
      PgEventstore.send(:init_variables)
    end

    context 'when admin web ui config is defined' do
      before do
        PgEventstore.configure(name: described_class::DEFAULT_ADMIN_UI_CONFIG) do |config|
          config.pg_uri = PgEventstore.config.pg_uri
          config.connection_pool_size = 2
        end
      end

      it 'uses it by default' do
        subject
        expect(last_response.body).not_to include('ConnectionPool::TimeoutError')
      end
    end

    context 'when admin web ui config is not defined' do
      it 'uses default config' do
        subject
        expect(last_response.body).to include('ConnectionPool::TimeoutError')
      end
    end
  end

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
    it_behaves_like 'admin web ui config'

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

    context 'when filtering by "$streams" system stream' do
      let(:params) { { filter: { system_stream: "$streams" } } }

      it 'displays 0-stream revision events' do
        subject
        expect(rendered_event_ids).to eq([events2.first.id, events1.first.id])
      end
    end

    describe 'resolving links' do
      let!(:events1) do
        PgEventstore.client.append_to_stream(stream1, [PgEventstore::Event.new(type: "Foo")])
      end
      let!(:events2) do
        PgEventstore.client.link_to(stream2, [events1.first])
      end

      context 'when :resolve_link_tos param has "true" value' do
        let(:params) { { resolve_link_tos: 'true' } }

        it 'resolves link events' do
          subject
          expect(rendered_event_ids).to eq(events1.map(&:id) * 2)
        end
      end

      context 'when :resolve_link_tos param has "false" value' do
        let(:params) { { resolve_link_tos: 'false' } }

        it 'displays link events' do
          subject
          expect(rendered_event_ids).to eq(events.map(&:id).reverse)
        end
      end

      context 'when :resolve_link_tos is not provided' do
        it 'resolves link events' do
          subject
          expect(rendered_event_ids).to eq(events1.map(&:id) * 2)
        end
      end
    end
  end

  describe 'POST /change_config' do
    subject { post '/change_config', params }

    let(:params) { { config: :some_config } }

    after do
      PgEventstore.send(:init_variables)
    end

    context 'when config is recognizable' do
      before do
        PgEventstore.configure(name: :some_config) do |config|
          config.max_count = 100
        end
      end

      it 'persists it in cookies' do
        subject
        expect(last_response.headers['set-cookie']).to eq('current_config=some_config; httponly; samesite=lax')
      end
    end

    context 'when config is not recognizable' do
      context 'when admin web ui config is not defined' do
        it 'sets it to default' do
          subject
          expect(last_response.headers['set-cookie']).to eq('current_config=default; httponly; samesite=lax')
        end
      end

      context 'when admin web ui config is defined' do
        before do
          PgEventstore.configure(name: described_class::DEFAULT_ADMIN_UI_CONFIG) do |config|
            config.pg_uri = PgEventstore.config.pg_uri
            config.connection_pool_size = 2
          end
        end

        it 'uses it by default' do
          subject
          expect(last_response.headers['set-cookie']).to(
            eq("current_config=#{described_class::DEFAULT_ADMIN_UI_CONFIG}; httponly; samesite=lax")
          )
        end
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
    it_behaves_like 'admin web ui config'

    context 'when there are more results than in current response' do
      before do
        stub_const('PgEventstore::Web::Paginator::StreamContextsCollection::PER_PAGE', 2)
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
    it_behaves_like 'admin web ui config'

    context 'when there are more results than in current response' do
      before do
        stub_const('PgEventstore::Web::Paginator::StreamNamesCollection::PER_PAGE', 2)
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
    it_behaves_like 'admin web ui config'

    context 'when there are more results than in current response' do
      before do
        stub_const('PgEventstore::Web::Paginator::StreamIdsCollection::PER_PAGE', 2)
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
    it_behaves_like 'admin web ui config'

    context 'when there are more results than in current response' do
      before do
        stub_const('PgEventstore::Web::Paginator::EventTypesCollection::PER_PAGE', 2)
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

  describe 'GET /subscriptions' do
    subject { get '/subscriptions', params }

    let(:params) { {} }

    let!(:set1) { SubscriptionsSetHelper.create(name: 'FooSet') }
    let!(:set2) { SubscriptionsSetHelper.create_with_connection(name: 'BarSet') }

    let!(:subscription1) { SubscriptionsHelper.create(locked_by: set1.id, set: set1.name, name: 'Sub1') }
    let!(:subscription2) do
      SubscriptionsHelper.create_with_connection(locked_by: set2.id, set: set2.name, name: 'Sub2')
    end

    context 'when no specific set is given' do
      it 'displays subscriptions of first set which goes in alphabetic order' do
        subject
        aggregate_failures do
          expect(last_response.body).not_to include(subscription1.name)
          expect(last_response.body).to include(subscription2.name)
        end
      end
      it 'displays all sets' do
        subject
        aggregate_failures do
          expect(last_response.body).to include(set1.name)
          expect(last_response.body).to include(set2.name)
        end
      end

      context 'when subscription is not locked' do
        before do
          subscription2.locked_by = nil
          subscription2.update(locked_by: nil)
        end

        it 'still displays it' do
          subject
          expect(last_response.body).to include(subscription2.name)
        end
      end
    end

    context 'when specific set is given' do
      let(:params) { { set_name: 'FooSet' } }

      it 'displays its subscriptions' do
        subject
        expect(last_response.body).to include(subscription1.name)
      end
    end

    context 'when subscription is stopped' do
      before do
        subscription2.update(state: 'stopped')
      end

      it 'displays it' do
        subject
        start_btn = nokogiri_body.css(
          "a[href='http://#{current_session.default_host}/subscription_cmd/#{set2.id}/#{subscription2.id}/Start']"
        ).first
        reset_position_btn = nokogiri_body.css(
          "a[data-url='http://#{current_session.default_host}/subscription_cmd/#{set2.id}/#{subscription2.id}/ResetPosition']"
        ).first
        aggregate_failures do
          expect(last_response.body).to include(subscription2.name)
          expect(start_btn).not_to be_nil, "Start button must be present"
          expect(reset_position_btn).not_to be_nil, "Reset position button must be present"
        end
      end
    end

    context 'when subscription is dead' do
      before do
        subscription2.update(state: 'dead')
      end

      it 'displays it' do
        subject
        stop_btn = nokogiri_body.css(
          "a[href='http://#{current_session.default_host}/subscription_cmd/#{set2.id}/#{subscription2.id}/Stop']"
        ).first
        restore_btn = nokogiri_body.css(
          "a[href='http://#{current_session.default_host}/subscription_cmd/#{set2.id}/#{subscription2.id}/Restore']"
        ).first
        aggregate_failures do
          expect(last_response.body).to include(subscription2.name)
          expect(stop_btn).not_to be_nil, "Stop button must be present"
          expect(restore_btn).not_to be_nil, "Restore button must be present"
        end
      end
    end

    context 'when subscription is running' do
      before do
        subscription2.update(state: 'running')
      end

      it 'displays it' do
        subject
        stop_btn = nokogiri_body.css(
          "a[href='http://#{current_session.default_host}/subscription_cmd/#{set2.id}/#{subscription2.id}/Stop']"
        ).first
        aggregate_failures do
          expect(last_response.body).to include(subscription2.name)
          expect(stop_btn).not_to be_nil, "Stop button must be present"
        end
      end
    end

    context 'when subscription is stopped and unlocked' do
      before do
        subscription2.update(state: 'stopped')
        set2.delete
      end

      it 'displays it' do
        subject
        delete_btn = nokogiri_body.css(
          "a[href='http://#{current_session.default_host}/delete_subscription/#{subscription2.id}']"
        ).first
        aggregate_failures do
          expect(last_response.body).to include(subscription2.name)
          expect(delete_btn).not_to be_nil, "Delete button must be present"
        end
      end
    end
  end

  describe 'GET /subscriptions/:state' do
    subject { get "/subscriptions/#{state}", params }

    let(:params) { {} }
    let(:state) { 'running' }

    let!(:set1) { SubscriptionsSetHelper.create(name: 'FooSet') }
    let!(:set2) { SubscriptionsSetHelper.create(name: 'BarSet') }

    let!(:subscription1) { SubscriptionsHelper.create(locked_by: set2.id, set: set1.name, name: 'Sub1') }
    let!(:subscription2) do
      SubscriptionsHelper.create(locked_by: set2.id, set: set2.name, name: 'Sub2', state: state)
    end

    it 'displays subscriptions with the given state only' do
      subject
      aggregate_failures do
        expect(last_response.body).not_to include(subscription1.name)
        expect(last_response.body).to include(subscription2.name)
      end
    end
    it 'it displays sets which relates to the subscriptions with the given state' do
      subject
      aggregate_failures do
        expect(last_response.body).not_to include(set1.name)
        expect(last_response.body).to include(set2.name)
      end
    end
    it_behaves_like 'admin web ui config'
  end

  describe 'POST /subscription_cmd/:set_id/:id/:cmd' do
    subject { post "/subscription_cmd/#{set.id}/#{subscription.id}/#{cmd}" }

    let!(:set) { SubscriptionsSetHelper.create }
    let!(:subscription) { SubscriptionsHelper.create }
    let(:cmd) { 'Stop' }

    let(:cmd_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    it_behaves_like 'admin web ui config'

    context 'when command is recognizable' do
      it 'creates a command record' do
        expect { subject }.to change {
          cmd_queries.find_by(
            subscription_id: subscription.id, subscriptions_set_id: set.id, command_name: cmd
          )&.options_hash
        }.to(a_hash_including(subscription_id: subscription.id, subscriptions_set_id: set.id, name: cmd))
      end
      it 'redirects to subscriptions page' do
        subject
        aggregate_failures do
          expect(last_response).to be_redirect
          expect(URI(last_response.location).path).to eq('/subscriptions')
        end
      end
    end

    context 'when command is not recognizable' do
      let(:cmd) { 'Stopit!' }

      it 'renders error' do
        subject
        expect(last_response.body).to include("<h2>Subscription command &quot;#{cmd}&quot; does not exist</h2>")
      end
    end
  end

  describe 'POST /subscriptions_set_cmd/:id/:cmd' do
    subject { post "/subscriptions_set_cmd/#{set.id}/#{cmd}" }

    let!(:set) { SubscriptionsSetHelper.create }
    let(:cmd) { 'Stop' }

    let(:cmd_queries) { PgEventstore::SubscriptionsSetCommandQueries.new(PgEventstore.connection) }

    it_behaves_like 'admin web ui config'

    context 'when command is recognizable' do
      it 'creates a command record' do
        expect { subject }.to change {
          cmd_queries.find_by(subscriptions_set_id: set.id, command_name: cmd)&.options_hash
        }.to(a_hash_including(subscriptions_set_id: set.id, name: cmd))
      end
      it 'redirects to subscriptions page' do
        subject
        aggregate_failures do
          expect(last_response).to be_redirect
          expect(URI(last_response.location).path).to eq('/subscriptions')
        end
      end
    end

    context 'when command is not recognizable' do
      let(:cmd) { 'Stopit!' }

      it 'renders error' do
        subject
        expect(last_response.body).to include("<h2>SubscriptionsSet command &quot;#{cmd}&quot; does not exist</h2>")
      end
    end
  end

  describe 'POST /delete_subscriptions_set/:id' do
    subject { post "/delete_subscriptions_set/#{set.id}" }

    let!(:set) { SubscriptionsSetHelper.create }

    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    it_behaves_like 'admin web ui config'

    context 'when SubscriptionsSet exists' do
      it 'deletes it' do
        expect { subject }.to change { queries.find_by(id: set.id) }.to(nil)
      end
      it 'redirects to subscriptions page' do
        subject
        aggregate_failures do
          expect(last_response).to be_redirect
          expect(URI(last_response.location).path).to eq('/subscriptions')
        end
      end
    end

    context 'when SubscriptionsSet does not exist' do
      it 'redirects to subscriptions page' do
        subject
        aggregate_failures do
          expect(last_response).to be_redirect
          expect(URI(last_response.location).path).to eq('/subscriptions')
        end
      end
    end
  end

  describe 'POST /delete_subscription/:id' do
    subject { post "/delete_subscription/#{subscription.id}" }

    let!(:subscription) { SubscriptionsHelper.create }

    let(:queries) { PgEventstore::SubscriptionQueries.new(PgEventstore.connection) }

    it_behaves_like 'admin web ui config'

    context 'when Subscription exists' do
      it 'deletes it' do
        expect { subject }.to change { queries.find_by(id: subscription.id) }.to(nil)
      end
      it 'redirects to subscriptions page' do
        subject
        aggregate_failures do
          expect(last_response).to be_redirect
          expect(URI(last_response.location).path).to eq('/subscriptions')
        end
      end
    end

    context 'when Subscription does not exist' do
      it 'redirects to subscriptions page' do
        subject
        aggregate_failures do
          expect(last_response).to be_redirect
          expect(URI(last_response.location).path).to eq('/subscriptions')
        end
      end
    end
  end

  describe 'POST /delete_all_subscriptions' do
    subject { post '/delete_all_subscriptions', params }

    let(:params) { { ids: [subscription1.id, subscription2.id] } }

    let!(:subscription1) { SubscriptionsHelper.create(name: 'Sub1') }
    let!(:subscription2) { SubscriptionsHelper.create(name: 'Sub2') }
    let!(:subscription3) { SubscriptionsHelper.create(name: 'Sub3') }

    let(:queries) { PgEventstore::SubscriptionQueries.new(PgEventstore.connection) }

    it 'deletes first subscription' do
      expect { subject }.to change { queries.find_by(id: subscription1.id) }.to(nil)
    end
    it 'deletes second subscription' do
      expect { subject }.to change { queries.find_by(id: subscription2.id) }.to(nil)
    end
    it 'does not delete third subscription' do
      expect { subject }.not_to change { queries.find_by(id: subscription3.id) }
    end
    it_behaves_like 'admin web ui config'
  end
end
