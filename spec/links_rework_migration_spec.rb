# frozen_string_literal: true

RSpec.describe 'Migration to new links implementation' do
  before do
    create_db = <<~BASH
      docker exec -e PGPASSWORD=postgres pg_eventstore-postgres-main psql -U postgres \
      --command="CREATE DATABASE links_migration_tests"
    BASH
    restore_dump = <<~BASH
      cat spec/support/db_assets/events_before_links_rework.sql | docker exec -e PGPASSWORD=postgres \
      -i pg_eventstore-postgres-main psql -U postgres -d links_migration_tests
    BASH
    migrate_events = <<~BASH
      PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/links_migration_tests" bundle exec rake \
      pg_eventstore:migrate
    BASH
    `#{create_db}`
    `#{restore_dump}`
    `#{migrate_events}`
    PgEventstore.configure do |config|
      config.pg_uri = 'postgresql://postgres:postgres@localhost:5532/links_migration_tests'
    end
  end

  after do
    PgEventstore.connection.shutdown
    drop_db = <<~BASH
      docker exec -e PGPASSWORD=postgres -it pg_eventstore-postgres-main psql -U postgres \
      --command="DROP DATABASE links_migration_tests"
    BASH
    `#{drop_db}`
  end

  it 'migrates links properly' do
    link_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'BarProjection', stream_id: '1')
    link1 = PgEventstore::Event.new(
      id: 'aa160471-6d46-4d23-be50-5603719cd93a',
      type: '$>',
      global_position: 3,
      stream: PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'BarProjection', stream_id: '1'),
      stream_revision: 0,
      data: {},
      metadata: {},
      link_global_position: 1,
      link_partition_id: 3,
      link: nil,
      created_at: Time.parse('2025-12-29 19:16:06.774898 UTC')
    )
    link2 = PgEventstore::Event.new(
      id: '202c011e-6927-4e25-b080-1c49499dc7c7',
      type: '$>',
      global_position: 4,
      stream: PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'BarProjection', stream_id: '1'),
      stream_revision: 1,
      data: {},
      metadata: {},
      link_global_position: 2,
      link_partition_id: 3,
      link: nil,
      created_at: Time.parse('2025-12-29 19:16:06.774898 UTC')
    )
    aggregate_failures do
      expect(PgEventstore.client.read(link_stream)).to eq [link1, link2]
      expect(PgEventstore.client.read(link_stream, options: { resolve_link_tos: true })).to(
        eq(
          [
            PgEventstore::Event.new(
              id: '733fe342-ec8e-4837-ad87-897cbb2fe228',
              type: 'Foo',
              global_position: 1,
              stream: PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1'),
              stream_revision: 0,
              data: { 'foo' => 'foo' },
              metadata: {},
              link_global_position: nil,
              link_partition_id: nil,
              link: link1,
              created_at: Time.parse('2025-12-29 19:16:06.756458 UTC')
            ),
            PgEventstore::Event.new(
              id: '5756d3b1-78d4-4846-9cb4-427cd03d1049',
              type: 'Foo',
              global_position: 2,
              stream: PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2'),
              stream_revision: 0,
              data: { 'foo' => 'bar' },
              metadata: {},
              link_global_position: nil,
              link_partition_id: nil,
              link: link2,
              created_at: Time.parse('2025-12-29 19:16:06.760826 UTC')
            ),
          ]
        )
      )
    end
  end
end
