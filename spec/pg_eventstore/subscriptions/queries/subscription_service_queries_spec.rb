# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionServiceQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#current_database_id' do
    subject { instance.current_database_id }

    let(:current_database) { URI.parse(PgEventstore.config.pg_uri).path[1..] }

    it 'returns id of the current database' do
      current_db_id = PgEventstore.connection.with do |c|
        c.exec_params('select oid from pg_database where datname = $1', [current_database])
      end.first['oid']
      is_expected.to eq(current_db_id)
    end
  end

  describe '#smallest_uncommitted_global_position' do
    subject { instance.smallest_uncommitted_global_position(db_id) }

    let(:db_id) { instance.current_database_id }

    context 'when lock originates from current database' do
      before do
        @locks = [2**33 + 1, 2**33 + 2, 2**32 + 4, 2**32 + 3].map do |num|
          Thread.new do
            PgEventstore.connection.with do |c|
              c.transaction do
                c.exec_params('SELECT pg_advisory_lock($1)', [num])
                sleep 0.5
              end
            end
          end
        end
      end

      after do
        @locks.each(&:join)
      end

      it 'returns smallest lock value' do
        sleep 0.1 # let threads to start and acquire locks
        is_expected.to eq(2**32 + 3)
      end
    end

    context 'when lock originates from different database' do
      before do
        uri = URI.parse(PgEventstore.config.pg_uri)
        uri.path = '/postgres'
        PgEventstore.configure(name: :another_db) do |conf|
          conf.pg_uri = uri.to_s
        end

        @lock1 = Thread.new do
          PgEventstore.connection(:another_db).with do |c|
            c.transaction do
              c.exec('SELECT pg_advisory_lock(1)')
              sleep 0.5
            end
          end
        end
        @lock2 = Thread.new do
          PgEventstore.connection.with do |c|
            c.transaction do
              c.exec('SELECT pg_advisory_lock(2)')
              sleep 0.5
            end
          end
        end
      end

      after do
        [@lock1, @lock2].each(&:join)
      end

      it 'does not take it into account' do
        sleep 0.1 # let threads to start and acquire locks
        is_expected.to eq(2)
      end
    end

    context 'when there are no locks' do
      it { is_expected.to eq(nil) }
    end
  end
end
