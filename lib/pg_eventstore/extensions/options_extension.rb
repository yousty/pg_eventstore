# frozen_string_literal: true

module PgEventstore
  module Extensions
    # A very simple extension that implements a DSL for adding attr_accessors with default values,
    # and assigning their values during object initialization.
    # Example. Let's say you frequently do something like this:
    #   class SomeClass
    #     attr_accessor :attr1, :attr2, :attr3, :attr4
    #
    #     def initialize(opts = {})
    #       @attr1 = opts[:attr1] || 'Attr 1 value'
    #       @attr2 = opts[:attr2] || 'Attr 2 value'
    #       @attr3 = opts[:attr3] || do_some_calc
    #       @attr4 = opts[:attr4]
    #     end
    #
    #     def do_some_calc
    #       "Some calculations"
    #     end
    #   end
    #
    #   SomeClass.new(attr1: 'hihi', attr4: 'byebye')
    #
    # You can replace the code above using the OptionsExtension:
    #   class SomeClass
    #     include PgEventstore::Extensions::OptionsExtension
    #
    #     option(:attr1) { 'Attr 1 value' }
    #     option(:attr2) { 'Attr 2 value' }
    #     option(:attr3) { do_some_calc }
    #     option(:attr4)
    #
    #     def do_some_calc
    #       "Some calculations"
    #     end
    #   end
    #
    #   SomeClass.new(attr1: 'hihi', attr4: 'byebye')
    module OptionsExtension
      class Option
        attr_reader :name, :metadata

        # @param name [Symbol]
        # @param metadata [Object, nil]
        def initialize(name, metadata: nil)
          @name = name
          @metadata = metadata
        end

        # @param other [Object]
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(Option)

          name == other.name
        end

        # @param other [Object]
        # @return [Boolean]
        def eql?(other)
          return false unless other.is_a?(Option)

          name.eql?(other.name)
        end

        # @return [Integer]
        def hash
          name.hash
        end
      end

      class Options
        include Enumerable

        attr_reader :options
        protected :options

        # @param options [Array<PgEventstore::Extensions::OptionsExtension::Option>]
        def initialize(options = [])
          @options = options.to_h { [_1, true] }
        end

        # @param option_name [Symbol]
        # @return [PgEventstore::Extensions::OptionsExtension::Option, nil]
        def [](option_name)
          options.assoc(Option.new(option_name))&.dig(0)
        end

        # @param other [PgEventstore::Extensions::OptionsExtension::Options]
        # @return [PgEventstore::Extensions::OptionsExtension::Options]
        def +(other)
          self.class.new(options.keys + other.options.keys)
        end

        # @param option [PgEventstore::Extensions::OptionsExtension::Option]
        # @return [Boolean]
        def include?(option)
          options.key?(option)
        end

        # @return [Boolean]
        def dup
          self.class.new(options.keys)
        end

        def each(...)
          options.keys.each(...)
        end

        def ==(other)
          options.keys == other.options.keys
        end
      end

      # @!visibility private
      module ClassMethods
        # @param opt_name [Symbol] option name
        # @param blk [Proc] provide define value using block. It will be later evaluated in the
        #   context of your object to determine the default value of the option
        # @return [Symbol]
        def option(opt_name, metadata: nil, &blk)
          self.options = (options + Options.new([Option.new(opt_name, metadata: metadata)])).freeze
          warn_already_defined(opt_name)
          warn_already_defined(:"#{opt_name}=")
          define_method "#{opt_name}=" do |value|
            readonly_error(opt_name) if readonly?(opt_name)

            instance_variable_set(:"@#{opt_name}", value)
          end

          define_method opt_name do
            result = instance_variable_get(:"@#{opt_name}")
            return result if instance_variable_defined?(:"@#{opt_name}")

            instance_exec(&blk) if blk
          end
        end
        alias attribute option

        def inherited(klass)
          super
          klass.options = options.dup.freeze
        end

        private

        # @param method_name [Symbol]
        # @return [void]
        def warn_already_defined(method_name)
          return unless instance_methods.include?(method_name)

          puts "Warning: Redefining already defined method #{self}##{method_name}"
        end
      end

      class ReadonlyAttributeError < StandardError
      end

      def self.included(klass)
        klass.singleton_class.attr_accessor(:options)
        klass.options = Options.new.freeze
        klass.extend(ClassMethods)
      end

      def initialize(**options)
        @readonly = Set.new
        init_default_values(options)
      end

      # Construct a hash from options, where key is the option's name and the value is option's
      # value
      # @return [Hash]
      def options_hash
        self.class.options.each_with_object({}) do |option, res|
          res[option.name] = public_send(option.name)
        end
      end
      alias attributes_hash options_hash

      # @param opt_name [Symbol]
      # @return [Boolean]
      def readonly!(opt_name)
        return false unless self.class.options.include?(Option.new(opt_name))

        @readonly.add(opt_name)
        true
      end

      # @param opt_name [Symbol]
      # @return [Boolean]
      def readonly?(opt_name)
        @readonly.include?(opt_name)
      end

      private

      # @param opt_name [Symbol]
      # @return [void]
      # @raise [PgEventstore::Extensions::OptionsExtension::ReadOnlyError]
      def readonly_error(opt_name)
        raise(
          ReadonlyAttributeError, "#{opt_name.inspect} attribute was marked as read only. You can no longer modify it."
        )
      end

      # @param options [Hash]
      # @return [void]
      def init_default_values(options)
        self.class.options.each do |option|
          # init default values of options
          value = options.key?(option.name) ? options[option.name] : public_send(option.name)
          public_send("#{option.name}=", value)
        end
      end
    end
  end
end
