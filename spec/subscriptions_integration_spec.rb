# frozen_string_literal: true

RSpec.describe 'Subscriptions integration' do
  describe 'events processing using default pull interval' do
    subject { manager.start }

    let(:manager) { PgEventstore.subscriptions_manager(subscription_set: set_name) }
    let(:set_name) { 'Microservice 1 Subscriptions' }

    let(:handler1) { proc { |event| processed_events1.push(event) } }
    let(:handler2) { proc { |event| processed_events2.push(event) } }
    let(:processed_events1) { [] }
    let(:processed_events2) { [] }
    let(:pull_interval) { 2 }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(data: { bar: :baz }, type: 'Bar') }

    before do
      PgEventstore.client.append_to_stream(stream, [event1, event2])
      PgEventstore.config.subscription_pull_interval = pull_interval
      manager.subscribe('Subscription 1', handler: handler1, options: { filter: { event_types: ['Foo'] } })
      manager.subscribe('Subscription 2', handler: handler2, options: { filter: { streams: [{ context: 'FooCtx' }] } })
    end

    after do
      manager.stop
      PgEventstore.send(:init_variables)
    end

    it 'processes events of first subscription' do
      expect { subject }.to change {
        dv(processed_events1).deferred_wait(timeout: pull_interval) { _1.size == 1 }
      }.to([PgEventstore.client.read(stream).first])
    end
    it 'processes events of second subscription' do
      expect { subject }.to change {
        dv(processed_events2).deferred_wait(timeout: pull_interval) { _1.size == 2 }
      }.to(PgEventstore.client.read(stream))
    end
  end

  describe 'overriding pull interval' do
    subject { manager.start }

    let(:manager) { PgEventstore.subscriptions_manager(subscription_set: set_name) }
    let(:set_name) { 'Microservice 1 Subscriptions' }

    let(:handler) { proc { |event| processed_events.push(event) } }
    let(:processed_events) { [] }
    let(:pull_interval) { 1 }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(data: { bar: :baz }, type: 'Bar') }

    before do
      PgEventstore.configure do |config|
        config.subscription_pull_interval = 3
      end

      manager.subscribe(
        'Subscription 1',
        handler: handler, options: { filter: { event_types: ['Foo'] } }, pull_interval: pull_interval
      )
      PgEventstore.client.append_to_stream(stream, [event1, event2])
    end

    after do
      manager.stop
      PgEventstore.send(:init_variables)
    end

    it 'processes events sooner than config.subscription_pull_interval' do
      expect { subject }.to change {
        dv(processed_events).deferred_wait(timeout: pull_interval) { _1.size == 1 }
      }.to([PgEventstore.client.read(stream).first])
    end
  end

  describe "overriding Subscription's max_retries" do
    subject { manager.start }

    let(:manager) { PgEventstore.subscriptions_manager(subscription_set: set_name) }
    let(:set_name) { 'Microservice 1 Subscriptions' }

    let(:handler) { proc { raise 'oops!' } }
    let(:max_retries) { 2 }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(data: { bar: :baz }, type: 'Bar') }

    before do
      PgEventstore.configure do |config|
        config.subscription_pull_interval = 0
        config.subscription_max_retries = 0
        config.subscription_retries_interval = 1
      end

      manager.subscribe(
        'Subscription 1',
        handler: handler, options: { filter: { event_types: ['Foo'] } }, max_retries: max_retries
      )
      PgEventstore.client.append_to_stream(stream, [event1, event2])
    end

    after do
      manager.stop
      PgEventstore.send(:init_variables)
    end

    it 'retries custom number of times' do
      subject
      # max_retries + 1 comes from the neediness to wait for the initial try
      sleep 0.6 + (max_retries + 1) * PgEventstore.config.subscription_retries_interval
      aggregate_failures do
        expect(manager.subscriptions.first.state).to eq('dead')
        expect(manager.subscriptions.first.restart_count).to eq(max_retries)
      end
    end
  end

  describe "overriding Subscription's retries_interval" do
    subject { manager.start }

    let(:manager) { PgEventstore.subscriptions_manager(subscription_set: set_name) }
    let(:set_name) { 'Microservice 1 Subscriptions' }

    let(:handler) { proc { raise 'oops!' } }
    let(:retries_interval) { 2 }
    let(:subscription_pull_interval) { 1 }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(data: { bar: :baz }, type: 'Bar') }

    before do
      PgEventstore.configure do |config|
        config.subscription_pull_interval = 1
        config.subscription_max_retries = 100
        config.subscription_retries_interval = 10
      end

      manager.subscribe(
        'Subscription 1',
        handler: handler, options: { filter: { event_types: ['Foo'] } }, retries_interval: retries_interval
      )
      PgEventstore.client.append_to_stream(stream, [event1, event2])
    end

    after do
      manager.stop
      PgEventstore.send(:init_variables)
    end

    it 'does the number of retries according to retries_interval' do
      subject
      # Number of retries to do before making assumptions.
      number_of_retries = 2
      sleep (number_of_retries + 1) * retries_interval
      aggregate_failures do
        expect(manager.subscriptions.first.state).to eq('dead')
        expect(manager.subscriptions.first.restart_count).to eq(number_of_retries)
      end
    end
  end

  describe 'overriding middlewares' do
    subject { manager.start }

    let(:manager) { PgEventstore.subscriptions_manager(subscription_set: set_name) }
    let(:set_name) { 'Microservice 1 Subscriptions' }

    let(:handler1) { proc { |event| processed_events1.push(event) } }
    let(:handler2) { proc { |event| processed_events2.push(event) } }
    let(:processed_events1) { [] }
    let(:processed_events2) { [] }
    let(:pull_interval) { 2 }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(data: { bar: :baz }, type: 'Bar') }

    before do
      PgEventstore.configure do |config|
        config.middlewares = { dummy: DummyMiddleware.new, dummy2: Dummy2Middleware.new }
        config.subscription_pull_interval = pull_interval
      end

      manager.subscribe('Subscription 1', handler: handler1, options: { filter: { event_types: ['Foo'] } })
      manager.subscribe(
        'Subscription 2',
        handler: handler2, options: { filter: { streams: [{ context: 'FooCtx' }] } },
        middlewares: %i[dummy2]
      )
      PgEventstore.client.append_to_stream(stream, [event1, event2])
    end

    after do
      manager.stop
      PgEventstore.send(:init_variables)
    end

    it 'processes events of first subscription taking into account overridden middlewares' do
      aggregate_failures do
        expect { subject }.to change {
          dv(processed_events1).deferred_wait(timeout: pull_interval) { _1.size == 1 }.size
        }.to(1)
        expect(processed_events1).to(
          all satisfy { |event| event.metadata['dummy_secret'] == DummyMiddleware::DECR_SECRET }
        )
        expect(processed_events1).to(
          all satisfy { |event| event.metadata['dummy2_secret'] == Dummy2Middleware::DECR_SECRET }
        )
      end
    end

    it 'processes events of second subscription taking into account overridden middlewares' do
      aggregate_failures do
        expect { subject }.to change {
          dv(processed_events2).deferred_wait(timeout: pull_interval) { _1.size == 1 }.size
        }.to(2)
        expect(processed_events2).to(
          all satisfy { |event| event.metadata['dummy_secret'] == DummyMiddleware::ENCR_SECRET }
        )
        expect(processed_events2).to(
          all satisfy { |event| event.metadata['dummy2_secret'] == Dummy2Middleware::DECR_SECRET }
        )
      end
    end
  end

  describe "overriding SubscriptionsSet's max_retries" do
    subject { manager.start }

    let(:manager) { PgEventstore.subscriptions_manager(subscription_set: set_name, max_retries: max_retries) }
    let(:set_name) { 'Microservice 1 Subscriptions' }
    let(:max_retries) { 2 }
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    before do
      PgEventstore.configure do |config|
        config.subscriptions_set_max_retries = 0
        config.subscriptions_set_retries_interval = 1
      end
      allow(PgEventstore::SubscriptionRunnersFeeder).to receive(:new).and_raise('Oops!')
    end

    after do
      manager.stop
      PgEventstore.send(:init_variables)
    end

    it 'retries custom number of times' do
      subject
      # - max_retries + 1 comes from the neediness to wait for the initial try
      # - PgEventstore.config.subscriptions_set_retries_interval + 1 comes from the neediness to wait for runner's run
      #   interval which is always 1 second
      sleep 0.6 + (max_retries + 1) * (PgEventstore.config.subscriptions_set_retries_interval + 1)
      aggregate_failures do
        expect(queries.find_by(name: set_name)&.dig(:state)).to eq('dead')
        expect(queries.find_by(name: set_name)&.dig(:restart_count)).to eq(max_retries)
      end
    end
  end

  describe 'events processing with :resolve_link_tos option' do
    subject { manager.start }

    let(:manager) { PgEventstore.subscriptions_manager(subscription_set: set_name) }
    let(:set_name) { 'Microservice 1 Subscriptions' }

    let(:handler) { proc { |event| processed_events.push(event) } }
    let(:processed_events) { [] }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:event1) do
      event = PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo')
      PgEventstore.client.append_to_stream(stream, event)
    end
    let(:event2) do
      event = PgEventstore::Event.new(data: { bar: :baz }, type: 'Bar')
      PgEventstore.client.append_to_stream(stream, event)
    end

    before do
      PgEventstore.client.link_to(stream, [event1, event2])
      PgEventstore.config.subscription_pull_interval = 0.2
      manager.subscribe(
        'Subscription 1',
        handler: handler, options: { filter: { streams: [{ context: 'FooCtx' }] }, resolve_link_tos: true }
      )
    end

    after do
      manager.stop
      PgEventstore.send(:init_variables)
    end

    it 'processes events correctly' do
      aggregate_failures do
        expect { subject }.to change { dv(processed_events).deferred_wait(timeout: 1) { _1.size == 4 }.size }.to(4)
        expect(processed_events.map(&:id)).to eq([event1, event2, event1, event2].map(&:id))
      end
    end
  end

  describe 'force-locking subscriptions' do
    subject { manager.start }

    let(:manager) { PgEventstore.subscriptions_manager(subscription_set: set_name, force_lock: true) }
    let(:set_name) { 'Microservice 1 Subscriptions' }

    let!(:existing_subscriptions_set) { SubscriptionsSetHelper.create_with_connection(name: set_name) }
    let!(:locked_subscription) do
      SubscriptionsHelper.create_with_connection(
        set: set_name, name: subscription_name, locked_by: existing_subscriptions_set.id
      )
    end
    let(:subscription_name) { 'Subscription 1' }

    let(:handler) { proc { |event| processed_events.push(event) } }
    let(:processed_events) { [] }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let!(:event) do
      event = PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo')
      PgEventstore.client.append_to_stream(stream, event)
    end

    let(:queries) do
      PgEventstore::SubscriptionQueries.new(PgEventstore.connection)
    end

    before do
      PgEventstore.config.subscription_pull_interval = 0.2
      manager.subscribe(
        subscription_name,
        handler: handler, options: { filter: { streams: [{ context: 'FooCtx' }] } }
      )
    end

    after do
      manager.stop
      PgEventstore.send(:init_variables)
    end

    it 'locks existing subscription under new SubscriptionsSet' do
      expect { subject }.to change { locked_subscription.reload.locked_by }.to(kind_of(Integer))
    end
    it 'does not create another subscription' do
      expect { subject }.not_to change { queries.find_all(set: set_name).size }
    end
    it 'processes events correctly' do
      expect { subject }.to change { dv(processed_events).deferred_wait(timeout: 1) { _1.size == 1 }.size }.by(1)
    end
  end
end
