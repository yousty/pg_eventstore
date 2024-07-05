# frozen_string_literal: true

module PgEventstore
  module Extensions
    module BaseCommandExtension
      def self.included(klass)
        super
        klass.extend(ClassMethods)

        # Detects whether command is a known command. Known commands are commands, inherited from Base class.
        # @return [Boolean]
        klass.define_singleton_method(:known_command?) do
          self < klass
        end
      end

      module ClassMethods
        # @param data [Hash]
        # @return [Hash]
        def parse_data(data)
          {}
        end
      end

      # @return [Integer]
      def hash
        options_hash.hash
      end

      # @param another [Object]
      # @return [Boolean]
      def eql?(another)
        return false unless another.is_a?(self.class)

        hash == another.hash
      end

      # @param another [Object]
      # @return [Boolean]
      def ==(another)
        return false unless another.is_a?(self.class)

        options_hash == another.options_hash
      end
    end
  end
end
