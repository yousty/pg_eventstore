# frozen_string_literal: true

RSpec.describe PgEventstore::AsyncQueryRunner do
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
end
