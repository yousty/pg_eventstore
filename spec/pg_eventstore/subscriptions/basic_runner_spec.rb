# frozen_string_literal: true

RSpec.describe PgEventstore::BasicRunner do
  let(:instance) do
    described_class.new(
      run_interval: run_interval,
      async_shutdown_time: async_shutdown_time,
      recovery_strategies: recovery_strategies
    )
  end
  let(:run_interval) { 1 }
  let(:async_shutdown_time) { 1 }
  let(:recovery_strategies) { [] }

  describe 'instance' do
    subject { instance }

    it { is_expected.to be_a(PgEventstore::Extensions::CallbacksExtension) }
  end

  describe '#start' do
    subject { instance.start }

    let(:before_cbx_task) { double('Before runner started') }
    let(:perform_async_task) { double('Async action') }
    let(:after_error_task) { double('After error happened') }
    let(:callbacks_definitions) do
      instance.define_callback(:before_runner_started, :before, proc { before_cbx_task.run })
      instance.define_callback(:process_async, :before, proc { perform_async_task.run })
      instance.define_callback(:after_runner_died, :before, proc { |error| after_error_task.run(error) })
    end
    let(:run_interval) { 0.6 }

    before do
      allow(before_cbx_task).to receive(:run)
      allow(perform_async_task).to receive(:run)
      allow(after_error_task).to receive(:run)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    shared_examples "asynchronous execution" do
      it 'changes state to "running"' do
        expect { subject }.to change { instance.state }.to('running')
      end
      it 'executes :before_runner_started action' do
        subject
        expect(before_cbx_task).to have_received(:run).once
      end
      it 'performs :process_async action asynchronous' do
        subject
        sleep 1
        aggregate_failures do
          expect(perform_async_task).to have_received(:run).once
          sleep 0.5
          # After half a second we perform the same test over the same object, but with different expectation to prove
          # that the action is actually asynchronous
          expect(perform_async_task).to have_received(:run).twice
        end
      end

      context "when error happens during the runner's work" do
        let(:error) { StandardError.new('Time to die, you filthy runner!') }
        let(:run_interval) { 0.2 }

        before do
          times_executed = 0
          allow(perform_async_task).to receive(:run) do
            times_executed += 1
            raise(error) if times_executed == 2
          end
        end

        it 'performs :after_runner_died' do
          subject
          sleep 0.5
          aggregate_failures do
            # :perform async action fails on second run - we defined this condition in the stub above
            expect(perform_async_task).to have_received(:run).twice
            expect(after_error_task).to have_received(:run).with(error)
          end
        end
        it 'changes the state to "dead"' do
          expect { subject }.to change { dv(instance).deferred_wait(timeout: 0.5) { _1.state == 'dead' }.state }.to('dead')
        end
      end
    end

    context 'when state is "initial"' do
      before do
        callbacks_definitions
      end

      it_behaves_like 'asynchronous execution'
    end

    context 'when state is "stopped"' do
      before do
        instance.start.stop_async.wait_for_finish
        callbacks_definitions
      end

      it_behaves_like 'asynchronous execution'
    end

    context 'when state is "dead"' do
      let(:run_interval) { 0.01 }

      before do
        should_raise = true
        instance.define_callback(:process_async, :before, proc { raise("Something bad happened!") if should_raise })
        instance.start.wait_for_finish
        # Turn off the possible error raise. It will allow to potentially run another :perform_async action and prevent
        # false-positive test result
        should_raise = false
        callbacks_definitions
      end

      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { dv(instance).deferred_wait(timeout: 0.1) { _1.state == 'dead' }.state }
          expect(instance.state).to eq("dead")
        end
      end
      it 'does not run :before_runner_started action' do
        subject
        expect(before_cbx_task).not_to have_received(:run)
      end
      it 'does not run :process_async action' do
        subject
        sleep 0.1
        expect(perform_async_task).not_to have_received(:run)
      end
      it 'does not run :after_runner_died action' do
        subject
        sleep 0.1
        expect(after_error_task).not_to have_received(:run)
      end
    end

    context 'when state is "halting"' do
      before do
        instance.start
        callbacks_definitions
        dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
        instance.stop_async
      end

      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("halting")
        end
      end
      it 'does not run :before_runner_started action' do
        subject
        expect(before_cbx_task).not_to have_received(:run)
      end
    end

    context 'when state is "running"' do
      before do
        instance.start
        callbacks_definitions
      end

      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("running")
        end
      end
      it 'does not run :before_runner_started action' do
        subject
        expect(before_cbx_task).not_to have_received(:run)
      end
    end

    describe 'error in :change_state callback' do
      subject do
        super()
      rescue error_class
      end

      let(:error_class) { Class.new(StandardError) }

      before do
        should_raise = true
        instance.define_callback(
          :change_state, :before,
          proc {
            if should_raise
              should_raise = false
              raise error_class, "That's unexpected!"
            end
          }
        )
        callbacks_definitions
      end

      it_behaves_like 'asynchronous execution'
    end
  end

  describe '#stop' do
    subject { instance.stop }

    let(:after_stopped_task) { double('After runner is stopped') }
    let(:perform_async_results) { [] }
    let(:run_interval) { 0.2 }
    let(:callbacks_definitions) do
      instance.define_callback(:after_runner_stopped, :before, proc { after_stopped_task.run })
      instance.define_callback(:process_async, :before, proc { perform_async_results.push(:the_result) })
    end

    before do
      allow(after_stopped_task).to receive(:run)
    end

    context 'when state is "initial"' do
      before do
        callbacks_definitions
      end

      it 'does not execute :after_runner_stopped action' do
        subject
        expect(after_stopped_task).not_to have_received(:run)
      end
      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("initial")
        end
      end
    end

    context 'when state is "stopped"' do
      before do
        instance.start.stop_async.wait_for_finish
        callbacks_definitions
      end

      it 'does not execute :after_runner_stopped action' do
        subject
        expect(after_stopped_task).not_to have_received(:run)
      end
      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("stopped")
        end
      end
    end

    context 'when state is "hating"' do
      before do
        callbacks_definitions
        instance.start
        dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
        instance.stop_async
      end

      after do
        instance.wait_for_finish
      end

      it 'does not execute :after_runner_stopped action' do
        subject
        expect(after_stopped_task).not_to have_received(:run)
      end
      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("halting")
        end
      end
    end

    context 'when state is "running"' do
      before do
        callbacks_definitions
        instance.start
        dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      end

      it 'executes :after_runner_stopped action' do
        subject
        expect(after_stopped_task).to have_received(:run)
      end
      it 'changes the state to "stopped"' do
        expect { subject }.to change { instance.state }.from("running").to("stopped")
      end
      it "releases runner's thread" do
        expect { subject }.to change { instance.instance_variable_get(:@runner) }.from(instance_of(Thread)).to(nil)
      end
      it 'stops runners from processing further' do
        subject
        expect { sleep run_interval }.not_to change { perform_async_results.size }
      end
    end

    context 'when state is "dead"' do
      before do
        callbacks_definitions
        instance.define_callback(:process_async, :before, proc { raise "You shall not pass!" })
        instance.start
        dv(instance).wait_until(timeout: run_interval + 0.1) { _1.state == 'dead' }
      end

      it 'executes :after_runner_stopped action' do
        subject
        expect(after_stopped_task).to have_received(:run)
      end
      it 'changes the state to "stopped"' do
        expect { subject }.to change { instance.state }.from("dead").to("stopped")
      end
      it "releases runner's thread" do
        expect { subject }.to change { instance.instance_variable_get(:@runner) }.from(instance_of(Thread)).to(nil)
      end
      it 'stops runners from processing further' do
        subject
        expect { sleep run_interval }.not_to change { perform_async_results.size }
      end
    end
  end

  describe '#stop_async' do
    subject { instance.stop_async }

    let(:async_shutdown_time) { 0.5 }
    let(:run_interval) { 0.2 }

    after do
      instance.wait_for_finish
    end

    describe 'normal execution' do
      let(:after_stopped_task) { double('After runner is stopped') }
      let(:perform_async_results) { [] }
      let(:callbacks_definitions) do
        instance.define_callback(:after_runner_stopped, :before, proc { after_stopped_task.run })
        instance.define_callback(:process_async, :before, proc { perform_async_results.push(:the_result) })
      end

      before do
        allow(after_stopped_task).to receive(:run)
      end

      context 'when state is "initial"' do
        it 'does not spawn another async job to stop the runner' do
          expect { subject }.not_to change { Thread.list }
        end
        it 'change the state to "halting"' do
          expect { subject }.not_to change { instance.state }
        end
      end

      context 'when state is "stopped"' do
        before do
          instance.start.stop
          dv(instance).wait_until(timeout: 0.2) { _1.state == 'stopped' }
        end

        it 'does not spawn another async job to stop the runner' do
          expect { subject }.not_to change { Thread.list }
        end
        it 'change the state to "halting"' do
          expect { subject }.not_to change { instance.state }
        end
      end

      context 'when state is "hating"' do
        before do
          instance.start.stop_async
        end

        it 'does not spawn another async job to stop the runner' do
          expect { subject }.not_to change { Thread.list }
        end
        it 'change the state to "halting"' do
          expect { subject }.not_to change { instance.state }
        end
      end

      context 'when state is "running"' do
        # Adds some extra time needed ruby to apply changes from background thread to current thread
        let(:test_adjustment_time) { 0.2 }

        before do
          callbacks_definitions
          instance.start
          dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
        end

        it 'spawns another thread to stop the current runner' do
          expect { subject }.to change { Thread.list.size }.by(1)
        end
        it 'executes :after_runner_stopped action asynchronous' do
          subject
          aggregate_failures do
            expect(after_stopped_task).not_to have_received(:run)
            sleep async_shutdown_time + test_adjustment_time
            expect(after_stopped_task).to have_received(:run)
          end
        end
        it 'changes the state to "halting"' do
          expect { subject }.to change { instance.state }.from("running").to("halting")
        end
        it 'changes the state to "stopped" after async_shutdown_time seconds' do
          timeout = async_shutdown_time + test_adjustment_time
          expect { subject }.to change {
            dv(instance).deferred_wait(timeout: timeout) { _1.state == 'stopped' }.state
          }.from("running").to("stopped")
        end
        it "releases runner's thread pointer after async_shutdown_time seconds" do
          timeout = async_shutdown_time + test_adjustment_time
          expect { subject }.to change {
            dv(instance).deferred_wait(timeout: timeout) {
              _1.instance_variable_get(:@runner).nil?
            }.instance_variable_get(:@runner)
          }.from(instance_of(Thread)).to(nil)
        end
        it "removes runner's thread" do
          subject
          thread = instance.instance_variable_get(:@runner)
          aggregate_failures do
            expect(Thread.list).to include(thread)
            sleep async_shutdown_time
            expect(Thread.list).not_to include(thread)
          end
        end
        it 'stops runners from processing further' do
          subject
          sleep async_shutdown_time
          expect { sleep run_interval }.not_to change { perform_async_results.size }
        end
      end

      context 'when state is "dead"' do
        before do
          callbacks_definitions
          instance.define_callback(:process_async, :before, proc { raise "You shall not pass!" })
          instance.start
          # The thread which spawns to stop the current runner is to fast. It uses #loop method internally - slow it down
          # a bit to give tests the time to perform assertions
          allow(instance).to receive(:loop).and_wrap_original do |orig_method, *args, **kwargs, &blk|
            sleep 0.2
            orig_method.call(*args, **kwargs, &blk)
          end
          instance.wait_for_finish # let the runner die
        end

        it 'spawns another thread to stop the current runner' do
          expect { subject }.to change { Thread.list.size }.by(1)
        end
        it 'executes :after_runner_stopped action asynchronous' do
          subject
          aggregate_failures do
            expect(after_stopped_task).not_to have_received(:run)
            sleep async_shutdown_time
            expect(after_stopped_task).to have_received(:run)
          end
        end
        it 'changes the state to "halting"' do
          expect { subject }.to change { instance.state }.from("dead").to("halting")
        end
        it 'changes the state to "stopped" after async_shutdown_time seconds' do
          expect { subject }.to change {
            dv(instance).deferred_wait(timeout: async_shutdown_time) { _1.state == 'stopped' }.state
          }.from('dead').to('stopped')
        end
        it "releases runner's thread pointer after async_shutdown_time seconds" do
          expect { subject }.to change {
            dv(instance).deferred_wait(timeout: async_shutdown_time) {
              _1.instance_variable_get(:@runner).nil?
            }.instance_variable_get(:@runner)
          }.from(instance_of(Thread)).to(nil)
        end
        it "does not include runner's thread in the threads list" do
          subject
          thread = instance.instance_variable_get(:@runner)
          expect(Thread.list).not_to include(thread)
        end
      end
    end

    describe 'error in :change_state callback' do
      subject do
        super()
      rescue error_class
      end

      let(:after_stopped_task) { double('After runner is stopped') }
      let(:perform_async_results) { [] }

      let(:error_class) { Class.new(StandardError) }

      # Adds some extra time needed ruby to apply changes from background thread to current thread
      let(:test_adjustment_time) { 0.2 }

      before do
        allow(after_stopped_task).to receive(:run)
        instance.define_callback(:after_runner_stopped, :before, proc { after_stopped_task.run })
        instance.define_callback(:process_async, :before, proc { perform_async_results.push(:the_result) })
        instance.start
        instance.define_callback(
          :change_state, :before,
          proc {
            # Disable stderr outputs
            Thread.report_on_exception = false
            raise error_class, "That's unexpected!"
          }
        )
        dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      end

      it 'spawns another thread to stop the current runner' do
        expect { subject }.to change { Thread.list.size }.by(1)
      end
      it 'does not executes :after_runner_stopped action' do
        subject
        dv(instance).wait_until(timeout: async_shutdown_time) { instance.stopped? }
        expect(after_stopped_task).not_to have_received(:run)
      end
      it 'changes the state to "halting"' do
        expect { subject }.to change { instance.state }.from("running").to("halting")
      end
      it 'changes the state to "stopped" after async_shutdown_time seconds' do
        timeout = async_shutdown_time + test_adjustment_time
        expect { subject }.to change {
          dv(instance).deferred_wait(timeout: timeout) { _1.state == 'stopped' }.state
        }.from("running").to("stopped")
      end
      it "releases runner's thread pointer after async_shutdown_time seconds" do
        timeout = async_shutdown_time + test_adjustment_time
        expect { subject }.to change {
          dv(instance).deferred_wait(timeout: timeout) {
            _1.instance_variable_get(:@runner).nil?
          }.instance_variable_get(:@runner)
        }.from(instance_of(Thread)).to(nil)
      end
      it "removes runner's thread" do
        subject
        thread = instance.instance_variable_get(:@runner)
        aggregate_failures do
          expect(Thread.list).to include(thread)
          sleep async_shutdown_time
          expect(Thread.list).not_to include(thread)
        end
      end
      it 'stops runners from processing further' do
        subject
        sleep async_shutdown_time
        expect { sleep run_interval }.not_to change { perform_async_results.size }
      end
    end
  end

  describe '#restore' do
    subject { instance.restore }

    let(:before_cbx_task) { double('Before runner restored') }
    let(:perform_async_task) { double('Async action') }
    let(:after_error_task) { double('After error happened') }
    let(:callbacks_definitions) do
      instance.define_callback(:before_runner_restored, :before, proc { before_cbx_task.run })
      instance.define_callback(:process_async, :before, proc { perform_async_task.run })
      instance.define_callback(:after_runner_died, :before, proc { |error| after_error_task.run(error) })
    end
    let(:run_interval) { 0.6 }

    before do
      allow(before_cbx_task).to receive(:run)
      allow(perform_async_task).to receive(:run)
      allow(after_error_task).to receive(:run)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    context 'when state is "initial"' do
      before do
        callbacks_definitions
      end

      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("initial")
        end
      end
      it 'does not run :before_runner_restored action' do
        subject
        expect(before_cbx_task).not_to have_received(:run)
      end
    end

    context 'when state is "stopped"' do
      before do
        instance.start.stop_async.wait_for_finish
        callbacks_definitions
      end

      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("stopped")
        end
      end
      it 'does not run :before_runner_restored action' do
        subject
        expect(before_cbx_task).not_to have_received(:run)
      end
    end

    context 'when state is "dead"' do
      before do
        should_raise = true
        instance.define_callback(:process_async, :before, proc { raise("Something bad happened!") if should_raise })
        instance.start.wait_for_finish
        # Turn off the possible error raise. It will allow to potentially run another :perform_async action and prevent
        # false-positive test result
        should_raise = false
        callbacks_definitions
      end

      it 'changes state to "running"' do
        expect { subject }.to change { instance.state }.from("dead").to("running")
      end
      it 'executes :before_runner_restored action' do
        subject
        expect(before_cbx_task).to have_received(:run).once
      end
      it 'performs :process_async action asynchronous' do
        subject
        sleep 1
        aggregate_failures do
          expect(perform_async_task).to have_received(:run).once
          sleep 0.5
          # After half a second we perform the same test over the same object, but with different expectation to prove
          # that the action is actually asynchronous
          expect(perform_async_task).to have_received(:run).twice
        end
      end

      context "when error happens during the runner's work" do
        let(:error) { StandardError.new('Time to die, you filthy runner!') }
        let(:run_interval) { 0.2 }

        before do
          times_executed = 0
          allow(perform_async_task).to receive(:run) do
            times_executed += 1
            raise(error) if times_executed == 2
          end
        end

        it 'performs :after_runner_died' do
          subject
          sleep 0.5
          aggregate_failures do
            # :perform async action fails on second run - we defined this condition in the stub above
            expect(perform_async_task).to have_received(:run).twice
            expect(after_error_task).to have_received(:run).with(error)
          end
        end
        it 'changes the state to "dead"' do
          aggregate_failures do
            expect(instance.state).to eq('dead')
            subject
            expect(instance.state).to eq('running')
            sleep 0.5
            expect(instance.state).to eq('dead')
          end
        end
      end
    end

    context 'when state is "halting"' do
      before do
        instance.start
        dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
        instance.stop_async
        callbacks_definitions
      end

      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("halting")
        end
      end
      it 'does not run :before_runner_restored action' do
        subject
        expect(before_cbx_task).not_to have_received(:run)
      end
    end

    context 'when state is "running"' do
      before do
        instance.start
        callbacks_definitions
      end

      it 'does not change the state' do
        aggregate_failures do
          expect { subject }.not_to change { instance.state }
          expect(instance.state).to eq("running")
        end
      end
      it 'does not run :before_runner_restored action' do
        subject
        expect(before_cbx_task).not_to have_received(:run)
      end
    end
  end

  describe '#wait_for_finish' do
    subject { instance.wait_for_finish }

    context 'when state is "initial"' do
      before do
        instance.instance_variable_get(:@state).initial!
      end

      it 'instantly returns' do
        is_expected.to eq(instance)
      end
    end

    context 'when state is "stopped"' do
      before do
        instance.instance_variable_get(:@state).stopped!
      end

      it 'instantly returns' do
        is_expected.to eq(instance)
      end
    end

    context 'when state is "dead"' do
      before do
        instance.instance_variable_get(:@state).dead!
      end

      it 'instantly returns' do
        is_expected.to eq(instance)
      end
    end

    context 'when state is "running"' do
      before do
        instance.instance_variable_get(:@state).running!
      end

      it 'waits it to finish' do
        Thread.new do
          sleep 0.5
          instance.instance_variable_get(:@state).stopped!
        end

        expect { subject }.to change {
          dv(instance).deferred_wait(timeout: 0.6) { _1.state == 'stopped' }.state
        }.from('running').to('stopped')
      end
    end

    context 'when state is "halting"' do
      before do
        instance.instance_variable_get(:@state).halting!
      end

      it 'waits it to finish' do
        Thread.new do
          sleep 0.5
          instance.instance_variable_get(:@state).stopped!
        end

        expect { subject }.to change {
          dv(instance).deferred_wait(timeout: 0.6) { _1.state == 'stopped' }.state
        }.from('halting').to('stopped')
      end
    end
  end

  describe '#wait_for_finish and :after_runner_stopped action' do
    subject { instance.wait_for_finish }

    let(:after_stopped_cbx) do
      proc do
        # Add some delay to ensure the thread which runs #wait_for_finish is potentially already acknowledged about
        # state change, but dut to implementation it still waits for the :after_runner_stopped action to finish
        sleep 0.5
        REDIS.set('foo', 'bar')
      end
    end

    before do
      instance.define_callback(:after_runner_stopped, :after, after_stopped_cbx)
      instance.start.stop_async
    end

    it 'performs :after_runner_stopped action before stopping' do
      expect { subject }.to change { REDIS.get('foo') }.to('bar')
    end
  end

  describe '#withint_state' do
    subject { instance.within_state(state, &blk) }

    let(:blk) { proc { 123 } }
    let(:state) { :running }

    after do
      instance.stop_async.wait_for_finish
    end

    context 'when runner is in the given state' do
      before do
        instance.start
      end

      it 'yields the given block' do
        is_expected.to eq(123)
      end
    end

    context 'when runner is not in the given state' do
      it { is_expected.to eq(nil) }
    end

    context 'when state is unknown' do
      let(:state) { :foo }

      it 'raises error' do
        expect { subject }.to raise_error(KeyError, 'key not found: :foo')
      end
    end
  end

  describe 'self-recovery' do
    subject { sleep 0.4 }

    let(:before_restore_task) { double('Before runner restored') }
    let(:after_error_task) { double('After error happened') }
    let(:callbacks_definitions) do
      instance.define_callback(:before_runner_restored, :before, proc { before_restore_task.run })
      instance.define_callback(:process_async, :before, async_action)
      instance.define_callback(:after_runner_died, :before, proc { |error| after_error_task.run(error) })
    end
    let(:async_action) do
      should_raise = true
      proc do
        if should_raise
          should_raise = false
          raise error
        end
      end
    end

    let(:error) { StandardError.new("Regular") }

    let(:run_interval) { 0.1 }
    let(:seconds_before_recovery) { 0.2 }

    let(:start_runner) do
      # #let does not play well with threads. Thus, additionally wrap async function into a proc to call it lazily later
      proc do
        instance.start
        dv(instance).wait_until(timeout: run_interval) { _1.state == 'dead' }
      end
    end

    before do
      allow(before_restore_task).to receive(:run)
      allow(after_error_task).to receive(:run)
      callbacks_definitions
    end

    after do
      instance.stop_async.wait_for_finish
    end

    context 'when there is no recovery strategy from the given error' do
      before { start_runner.call }

      it 'does not recover the error' do
        expect { subject }.not_to change { instance.state }.from('dead')
      end
      it 'runs :after_runner_died callbacks' do
        subject
        expect(after_error_task).to have_received(:run).with(error)
      end
      it 'does not run :before_runner_restored callback' do
        subject
        expect(before_restore_task).not_to have_received(:run)
      end
    end

    context 'when there is a recovery strategy from the given error' do
      let(:recovery_strategies) do
        [
          DummyErrorRecovery.new(
            seconds_before_recovery: seconds_before_recovery,
            mocked_action: recovery_task,
            recoverable_message: error.message
          )
        ]
      end
      let(:recovery_task) { double('Additional recovery steps') }

      before do
        allow(recovery_task).to receive(:run)
        start_runner.call
      end

      it 'runs :after_runner_died callbacks' do
        subject
        expect(after_error_task).to have_received(:run).with(error)
      end
      it 'runs :before_runner_restored callback' do
        subject
        expect(before_restore_task).to have_received(:run)
      end
      it 'recovers from the error' do
        expect { subject }.to change { instance.state }.from('dead').to('running')
      end
      it 'runs recovery function' do
        subject
        expect(recovery_task).to have_received(:run)
      end
    end

    context 'when there are several recovery strategies' do
      let(:recovery_strategies) { [strategy1, strategy2, strategy3] }

      let(:strategy1) do
        DummyErrorRecovery.new(
          seconds_before_recovery: seconds_before_recovery,
          mocked_action: recovery_task1,
          recoverable_message: 'Some error'
        )
      end
      let(:strategy2) do
        DummyErrorRecovery.new(
          seconds_before_recovery: seconds_before_recovery,
          mocked_action: recovery_task2,
          recoverable_message: error.message
        )
      end
      let(:strategy3) do
        DummyErrorRecovery.new(
          seconds_before_recovery: seconds_before_recovery,
          mocked_action: recovery_task3,
          recoverable_message: error.message
        )
      end

      let(:recovery_task1) { double('Additional recovery steps 1') }
      let(:recovery_task2) { double('Additional recovery steps 2') }
      let(:recovery_task3) { double('Additional recovery steps 3') }

      before do
        allow(recovery_task1).to receive(:run)
        allow(recovery_task2).to receive(:run)
        allow(recovery_task3).to receive(:run)
        start_runner.call
        #p "here"
      end

      it 'runs :after_runner_died callbacks' do
        subject
        expect(after_error_task).to have_received(:run).with(error)
      end
      it 'runs :before_runner_restored callback' do
        subject
        expect(before_restore_task).to have_received(:run)
      end
      it 'recovers from the error' do
        expect { subject }.to change { instance.state }.from('dead').to('running')
      end
      it 'runs recovery function of first suitable strategy' do
        subject
        aggregate_failures do
          expect(recovery_task1).not_to have_received(:run)
          expect(recovery_task2).to have_received(:run)
          expect(recovery_task3).not_to have_received(:run)
        end
      end
    end

    context 'when error happens when starting the runner after recovery' do
      subject { sleep 0.6 }

      let(:recovery_strategies) do
        [
          DummyErrorRecovery.new(
            seconds_before_recovery: seconds_before_recovery,
            mocked_action: recovery_task,
            recoverable_message: error.message
          )
        ]
      end
      let(:recovery_task) { double('Additional recovery steps') }

      let(:deadly_change_state) do
        should_raise = true
        proc do
          if should_raise
            should_raise = false
            raise error
          end
        end
      end

      before do
        allow(recovery_task).to receive(:run)
        start_runner.call
        # This will trigger exception first time it is called inside a restore action
        instance.define_callback(:change_state, :before, deadly_change_state)
      end

      it 'runs :after_runner_died callbacks' do
        subject
        expect(after_error_task).to have_received(:run).with(error).twice
      end
      it 'runs :before_runner_restored callback' do
        subject
        expect(before_restore_task).to have_received(:run).twice
      end
      it 'recovers from the error' do
        expect { subject }.to change { instance.state }.from('dead').to('running')
      end
      it 'runs recovery function' do
        subject
        expect(recovery_task).to have_received(:run).twice
      end
    end
  end
end
