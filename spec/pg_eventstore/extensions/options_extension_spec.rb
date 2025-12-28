# frozen_string_literal: true

RSpec.describe PgEventstore::Extensions::OptionsExtension do
  let(:dummy_class) do
    klass = Class.new
    klass.include described_class
    klass
  end
  let(:instance) { dummy_class.new }

  describe 'defining option' do
    subject { dummy_class.option(option) }

    let(:option) { :some_opt }

    it 'defines reader' do
      subject
      expect(instance).to respond_to(option)
    end
    it 'defines writer' do
      subject
      expect(instance).to respond_to("#{option}=")
    end
    it 'adds that option to the options list' do
      expect { subject }.to change { dummy_class.options }.to(described_class::Options.new([described_class::Option.new(option)]))
    end
    it 'recognizes the given option when instantiating the class' do
      subject
      expect(dummy_class.new(option => 'some value').public_send(option)).to eq('some value')
    end

    context 'when block is provided' do
      subject { dummy_class.option(option, &blk) }

      let(:blk) { proc { 'some-value' } }

      before do
        allow(instance).to receive(:init_default_values)
      end

      it 'defines default value of option' do
        subject
        expect(instance.public_send(option)).to eq(blk.call)
      end
    end

    context 'when option has the same name as an existing method' do
      let(:option) { :__id__ }

      it 'outputs warning' do
        expect { subject }.to(
          output("Warning: Redefining already defined method #{dummy_class}##{option}\n").to_stdout
        )
      end
    end
  end

  describe 'defining option with metadata' do
    subject { dummy_class.option(option, metadata: metadata) }

    let(:option) { :some_opt }
    let(:metadata) { :my_awesome_metadata }

    context 'when option with same name but different metadata already exists' do
      let(:another_metadata) { :different_metadata }

      before do
        dummy_class.option(option, metadata: :different_metadata)
      end

      it 'does not override it' do
        subject
        aggregate_failures do
          expect(dummy_class.options).to eq(described_class::Options.new([described_class::Option.new(option)]))
          expect(dummy_class.options.map(&:metadata)).to eq([another_metadata])
        end
      end
    end
  end

  describe 'defining options in inherited class' do
    let(:child) { Class.new(dummy_class) }
    let(:child_of_child) { Class.new(child) }

    before do
      dummy_class.option(:parent_opt, metadata: :parent_opt_metadata)
      child.option(:child_opt, metadata: :child_opt_metadata)
      child_of_child.option(:child_of_child_opt, metadata: :child_of_child_opt_metadata)
    end

    it 'inherits all options from parent to the child correctly' do
      aggregate_failures do
        expect(child.options).to(
          eq(
            described_class::Options.new(
              [described_class::Option.new(:parent_opt), described_class::Option.new(:child_opt)]
            )
          )
        )
        expect(child.options.map(&:metadata)).to eq(%i[parent_opt_metadata child_opt_metadata])
      end
    end
    it 'inherits all options from parent to the child of child correctly' do
      aggregate_failures do
        expect(child_of_child.options).to(
          eq(
            described_class::Options.new(
              [
                described_class::Option.new(:parent_opt),
                described_class::Option.new(:child_opt),
                described_class::Option.new(:child_of_child_opt),
              ]
            )
          )
        )
        expect(child_of_child.options.map(&:metadata)).to(
          eq(%i[parent_opt_metadata child_opt_metadata child_of_child_opt_metadata])
        )
      end
    end
    it 'freezes options sets of children' do
      aggregate_failures do
        expect(child.options).to be_frozen
        expect(child_of_child.options).to be_frozen
      end
    end
    it "does not change parent's options" do
      aggregate_failures do
        expect(dummy_class.options).to eq described_class::Options.new([described_class::Option.new(:parent_opt)])
        expect(dummy_class.options.map(&:metadata)).to eq %i[parent_opt_metadata]
      end
    end
  end

  describe '.options' do
    subject { dummy_class.options }

    it { is_expected.to be_a(described_class::Options) }
    it { is_expected.to be_frozen }
  end

  describe 'getting an option by its name' do
    subject { dummy_class.options[:foo] }

    before do
      dummy_class.option(:foo, metadata: :bar)
    end

    it 'returns it' do
      aggregate_failures do
        expect(subject).to eq(described_class::Option.new(:foo))
        expect(subject.metadata).to eq(:bar)
      end
    end
  end

  describe '#options_hash' do
    subject { instance.options_hash }

    before do
      dummy_class.option(:opt1) { 'opt-1-value' }
      dummy_class.option(:opt2) { 'opt-2-value' }
    end

    it 'returns hash representation of options' do
      is_expected.to eq(opt1: 'opt-1-value', opt2: 'opt-2-value')
    end
  end

  describe 'assigning default values on initialize' do
    subject { instance.send(:initialize) }

    let(:dummy_class) do
      super().tap do |klass|
        klass.option(option, &proc { 'some value' })
      end
    end
    let(:option) { :str1 }
    let(:assigned_values) { [] }
    let(:instance) { dummy_class.allocate }

    before do
      allow(instance).to receive(:"#{option}=").and_wrap_original do |orig, value|
        assigned_values.push(value)
        orig.call(value)
      end
    end

    it 'assigns option value on initialize and memorizes it' do
      subject
      aggregate_failures do
        expect(instance).to have_received(:"#{option}=")
        expect(instance.public_send(option)).to eq('some value')
        expect(instance.public_send(option).__id__).to eq(assigned_values.last.__id__)
      end
    end
  end

  describe 'reader' do
    subject { instance.public_send(option) }

    let(:option) { :some_option }

    before do
      allow(instance).to receive(:init_default_values)
    end

    context 'when default value is not set' do
      before do
        dummy_class.option(option)
      end

      it { is_expected.to be_nil }
    end

    context 'when default value is set' do
      let(:blk) { proc { 'some-value' } }

      before do
        dummy_class.option(option, &blk)
      end

      it 'returns it' do
        is_expected.to eq(blk.call)
      end

      describe 'execution context of default value' do
        let(:blk) { proc { some_instance_method } }

        before do
          dummy_class.define_method(:some_instance_method) { 'some-instance-method-value' }
        end

        it 'processes it correctly' do
          is_expected.to eq('some-instance-method-value')
        end
      end

      context 'when option is marked as read-only' do
        before do
          instance.readonly!(option)
        end

        it 'returns it' do
          is_expected.to eq('some-value')
        end
      end
    end
  end

  describe 'writer' do
    subject { instance.public_send("#{option}=", 'new value') }

    let(:option) { :some_option }
    let(:dummy_class) do
      super().tap do |klass|
        klass.option(option, &proc { 'default value' })
      end
    end

    it 'changes default value' do
      expect { subject }.to change { instance.public_send(option) }.from('default value').to('new value')
    end

    context 'when option is marked as read-only' do
      before do
        instance.readonly!(option)
      end

      it 'raises error' do
        expect { subject }.to(
          raise_error(
            described_class::ReadonlyAttributeError,
            "#{option.inspect} attribute was marked as read only. You can no longer modify it."
          )
        )
      end
    end
  end

  describe '#readonly!' do
    subject { instance.readonly!(option) }

    let(:option) { :str1 }

    context 'when option exists' do
      let(:dummy_class) do
        super().tap do |klass|
          klass.option(option, &proc { 'some value' })
        end
      end

      it 'marks it as read-only' do
        expect { subject }.to change { instance.readonly?(option) }.to(true)
      end
    end

    context 'when option does not exist' do
      it 'does not mark it as read-only' do
        expect { subject }.not_to change { instance.readonly?(option) }
      end
    end
  end

  describe '#readonly?' do
    subject { instance.readonly?(option) }

    let(:option) { :str1 }

    context 'when option is defined' do
      let(:dummy_class) do
        super().tap do |klass|
          klass.option(option, &proc { 'some value' })
        end
      end

      context 'when option is marked as read-only' do
        before do
          instance.readonly!(option)
        end

        it { is_expected.to eq(true) }
      end

      context 'when option is not marked as read-only' do
        it { is_expected.to eq(false) }
      end
    end

    context 'when option is not defined' do
      it { is_expected.to eq(false) }
    end
  end
end
