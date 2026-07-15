# frozen_string_literal: true

RSpec.describe PgEventstore::AsyncRunner do
  let(:instance) { described_class.new }

  describe '#run' do
    subject { instance.run }

    let(:task1) do
      result = self.result
      proc do
        result.push('task1')
        Fiber.yield
        result.push('task1')
      end
    end
    let(:task2) do
      result = self.result
      proc do
        result.push('task2')
        Fiber.yield
        result.push('task2')
      end
    end
    let(:result) { [] }

    before do
      instance.async(&task1)
      instance.async(&task2)
    end

    it 'executes scheduled tasks until they are finished' do
      subject
      expect(result).to eq(%w[task1 task2 task1 task2])
    end
    it 'cleans up finished tasks' do
      expect { subject }.to change { instance.jobs_size }.to(0)
    end
  end

  describe '#run_once' do
    subject { instance.run_once }

    context 'when no error raises' do
      let(:task1) do
        result = self.result
        proc do
          result.push('task1')
          Fiber.yield
          result.push('task1')
        end
      end
      let(:task2) do
        result = self.result
        proc do
          result.push('task2')
          Fiber.yield
          result.push('task2')
        end
      end
      let(:task3) do
        result = self.result
        proc do
          result.push('task3')
        end
      end
      let(:result) { [] }

      before do
        instance.async(&task1)
        instance.async(&task2)
        instance.async(&task3)
      end

      it 'executes scheduled tasks until they yield control back to the runner' do
        subject
        expect(result).to eq(%w[task1 task2 task3])
      end
      it 'cleans up finished tasks' do
        expect { subject }.to change { instance.jobs_size }.to(2)
      end
    end

    context 'when error raises' do
      subject { instance.run_once }

      let(:task1) do
        proc do
          Fiber.yield
        end
      end
      let(:task2) do
        proc do
          raise 'Something'
        end
      end
      let(:task3) do
        proc do
          Fiber.yield
        end
      end

      before do
        instance.async(&task1)
        instance.async(&task2)
        instance.async(&task3)
      end

      it 'raises that error' do
        expect { subject }.to raise_error(RuntimeError, 'Something')
      end
      it 'clears jobs list' do
        expect {
          begin
            subject
          rescue RuntimeError
          end
        }.to change { instance.jobs_size }.to(0)
      end
    end
  end

  describe 'handling connections after an error in one of the running fibers' do
    subject { instance.run }

    let(:query_strategy) { PgEventstore::QueryStrategy::Async.new(PgEventstore.connection) }

    let(:task1) do
      query_strategy = self.query_strategy
      proc do
        query_strategy.exec('select pg_sleep(1)')
      end
    end
    let(:task2) do
      query_strategy = self.query_strategy
      proc do
        query_strategy.exec('foo bar')
        query_strategy.exec('select pg_sleep(1)')
      end
    end
    let(:task3) do
      query_strategy = self.query_strategy
      proc do
        query_strategy.exec('bar baz')
        query_strategy.exec('select pg_sleep(1)')
      end
    end

    before do
      PgEventstore.configure do |config|
        config.connection_pool_size = 3
      end

      instance.async(&task1)
      instance.async(&task2)
      instance.async(&task3)
    end

    it 'releases all connections after error is occurred' do
      start_time = Time.now
      begin
        subject
      rescue
      end

      aggregate_failures do
        expect(instance.jobs_size).to eq(0)
        result_from_released_connections = Array.new(3) do
          Thread.new { PgEventstore.connection.with { _1.exec('select 1 as one').first['one'] } }
        end.map(&:value)
        expect(result_from_released_connections).to eq([1, 1, 1]), 'Connections were not released properly'
        expect(Time.now - start_time).to(
          be < 0.1, 'Should not wait for the current queries to complete, but, it seems, it did'
        )
      end
    end
  end
end
