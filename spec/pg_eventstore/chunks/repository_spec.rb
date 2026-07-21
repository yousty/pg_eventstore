# frozen_string_literal: true

RSpec.describe PgEventstore::Chunks::Repository do
  let(:instance) { described_class.new }

  describe '#add_chunk' do
    subject { instance.add_chunk(chunk) }

    let(:chunk) { InstantChunk.new([1]) }

    it 'adds chunk' do
      expect { subject }.to change { instance.instance_variable_get(:@chunks) }.to([chunk])
    end

    context 'when condition is provided' do
      subject { instance.add_chunk(chunk, condition:) }

      let(:condition) { instance.new_cond }
      let(:result) { [] }

      let(:consumer1) do
        Thread.new do
          instance.synchronize do
            condition.wait_while { instance.instance_variable_get(:@chunks).empty? }
            result.push(:consumer1_called)
          end
        end
      end
      let(:consumer2) do
        Thread.new do
          instance.synchronize do
            condition.wait_while { instance.instance_variable_get(:@chunks).empty? }
            result.push(:consumer2_called)
          end
        end
      end

      before do
        dv(consumer1).wait_until(timeout: 0.5) { _1.status == 'sleep' }
        dv(consumer2).wait_until(timeout: 0.5) { _1.status == 'sleep' }
      end

      after do
        consumer1.exit
        consumer2.exit
      end

      it 'notifies consumers' do
        subject
        dv(result).wait_until(timeout: 0.5) { _1.size == 2 }
        expect(result).to match_array(%i[consumer1_called consumer2_called])
      end
      it 'adds chunk' do
        expect { subject }.to change { instance.instance_variable_get(:@chunks) }.to([chunk])
      end
    end

    context 'when instance is locked by mutex' do
      let(:condition) { instance.new_cond }

      let(:blocker) do
        Thread.new do
          instance.synchronize do
            sleep
          end
        end
      end
      let(:producer) { Thread.new { subject } }

      before do
        dv(blocker).wait_until(timeout: 0.5) { _1.status == 'sleep' }
      end

      after do
        blocker.exit
        producer.exit
      end

      it 'adds chunk' do
        expect { producer }.to change {
          dv(instance.instance_variable_get(:@chunks)).deferred_wait(timeout: 0.5) { _1.size == 1 }
        }.to([chunk])
      end
    end
  end

  describe '#clear' do
    subject { instance.clear }

    let(:chunk) { InstantChunk.new([1]) }

    before do
      instance.add_chunk(chunk)
      instance.add_chunk(chunk)
    end

    it 'removes all chunks' do
      expect { subject }.to change { instance.size }.from(2).to(0)
    end
  end

  describe '#size' do
    subject { instance.size }

    let(:chunk1) { InstantChunk.new([1]) }
    let(:chunk2) { InstantChunk.new([1, 2]) }

    before do
      instance.add_chunk(chunk1)
      instance.add_chunk(chunk2)
    end

    it 'returns sum of size of all chunks' do
      is_expected.to eq(3)
    end
  end

  describe '#empty?' do
    subject { instance.empty? }

    context 'when repository is empty' do
      it { is_expected.to eq(true) }
    end

    context 'when repository is not empty' do
      let(:chunk) { InstantChunk.new([1]) }

      before do
        instance.add_chunk(chunk)
      end

      it { is_expected.to eq(false) }
    end
  end

  describe '#consume_all' do
    subject { instance.consume_all }

    let(:chunk1) { InstantChunk.new([1]) }
    let(:chunk2) { LazyChunk.new([1, 2]) }

    before do
      instance.add_chunk(chunk1)
      instance.add_chunk(chunk2)
    end

    it 'returns Enumerator' do
      is_expected.to be_a(Enumerator)
    end
    it 'clears the repo' do
      expect { subject }.to change { instance.instance_variable_get(:@chunks) }.to([])
    end
    it 'contains all consumed entities' do
      expect(subject.to_a).to eq([1, 1, 2])
    end
  end

  describe '#wait_and_consume' do
    let(:condition) { instance.new_cond }
    let(:timeout) { 0.5 }
    let(:entities_to_consume) { 2 }

    context 'when no entities appear during the wait time' do
      subject { instance.wait_and_consume(entities_num: entities_to_consume, timeout:, condition:) }

      it { is_expected.to eq([]) }
      it 'waits up to :timeout seconds' do
        expect(PgEventstore::Utils.benchmark { subject }).to be_between(timeout, timeout + 0.1)
      end
    end

    context 'when new chunk arrives during the wait time' do
      let(:synchronizer) { Thread::Queue.new }
      let(:producer) do
        Thread.new do
          synchronizer.pop
          instance.add_chunk(chunk, condition:)
        end
      end
      let(:consumer) do
        Thread.new do
          result.push(*instance.wait_and_consume(entities_num: entities_to_consume, timeout:, condition:))
        end
      end
      let(:result) { [] }
      let(:chunk) { InstantChunk.new([1, 2, 3]) }

      before do
        dv(producer).wait_until(timeout: 0.2) { _1.status == 'sleep' }
      end

      after do
        producer.exit
        consumer.exit
      end

      it 'consumes the given amount of entities from it' do
        consumer
        aggregate_failures do
          expect { synchronizer.push(:sig) }.to change {
            dv(chunk).deferred_wait(timeout:) { _1.size == 1 }.size
          }.from(3).to(1)
          expect(result).to eq([1, 2])
        end
      end
      it 'does not wait for the whole timeout' do
        time_took = PgEventstore::Utils.benchmark do
          consumer
          synchronizer.push(:sig)
          dv(chunk).wait_until(timeout:) { _1.size == 1 }.size
        end
        expect(time_took).to be < 0.5
      end

      context 'when new chunk does not return all requested entities' do
        let(:chunk) { LazyChunk.new([1, 2, 3]) }

        it 'consumes the available amount of entities from it' do
          consumer
          aggregate_failures do
            expect { synchronizer.push(:sig) }.to change {
              dv(chunk).deferred_wait(timeout:) { _1.size == 2 }.size
            }.from(3).to(2)
            expect(result).to eq([1])
          end
        end
        it 'does not wait for the whole timeout' do
          time_took = PgEventstore::Utils.benchmark do
            consumer
            synchronizer.push(:sig)
            dv(chunk).wait_until(timeout:) { _1.size == 2 }.size
          end
          expect(time_took).to be < 0.5
        end
      end

      context 'when chunk gets drained' do
        let(:chunk) { InstantChunk.new([1, 2]) }

        it 'consumes all entities from it' do
          consumer
          aggregate_failures do
            expect { synchronizer.push(:sig) }.to change {
              dv(chunk).deferred_wait(timeout:, &:drained?).size
            }.from(2).to(0)
            expect(result).to eq([1, 2])
          end
        end
        it 'deletes drained chunk' do
          consumer
          synchronizer.push(:sig)
          dv(chunk).wait_until(timeout:, &:drained?)
          expect(instance).to be_empty
        end
      end
    end
  end
end
