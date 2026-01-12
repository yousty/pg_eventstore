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
      id: '25d31190-f665-4866-afdf-e200fefe9c18',
      type: '$>',
      global_position: 3,
      stream: PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'BarProjection', stream_id: '1'),
      stream_revision: 0,
      data: {},
      metadata: {},
      link_global_position: 1,
      link_partition_id: 3,
      link: nil,
      created_at: Time.parse('2026-01-12 21:28:54.102308 UTC')
    )
    link2 = PgEventstore::Event.new(
      id: '18265c54-0627-484f-88c7-7c53679881a9',
      type: '$>',
      global_position: 4,
      stream: PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'BarProjection', stream_id: '1'),
      stream_revision: 1,
      data: {},
      metadata: {},
      link_global_position: 2,
      link_partition_id: 3,
      link: nil,
      created_at: Time.parse('2026-01-12 21:28:54.102308 UTC')
    )
    aggregate_failures do
      expect(PgEventstore.client.read(link_stream)).to eq [link1, link2]
      expect(PgEventstore.client.read(link_stream, options: { resolve_link_tos: true })).to(
        eq(
          [
            PgEventstore::Event.new(
              id: 'da0b7cae-b04a-414b-aea3-58a985709947',
              type: 'Foo',
              global_position: 1,
              stream: PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1'),
              stream_revision: 0,
              data: { 'foo' => 'foo' },
              metadata: {},
              link_global_position: nil,
              link_partition_id: nil,
              link: link1,
              created_at: Time.parse('2026-01-12 21:28:54.081387 UTC')
            ),
            PgEventstore::Event.new(
              id: 'd14ee952-cb7b-4d09-b9ce-a53accdb7c55',
              type: 'Foo',
              global_position: 2,
              stream: PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2'),
              stream_revision: 0,
              data: { 'foo' => 'bar' },
              metadata: {},
              link_global_position: nil,
              link_partition_id: nil,
              link: link2,
              created_at: Time.parse('2026-01-12 21:28:54.08657 UTC')
            ),
          ]
        )
      )
    end
  end
end
