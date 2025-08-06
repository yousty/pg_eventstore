# frozen_string_literal: true

module PgEventstore
  module Extensions
    # @!visibility private
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
        # rubocop:disable Lint/UnusedMethodArgument
        def parse_data(data)
          {}
        end
        # rubocop:enable Lint/UnusedMethodArgument
      end

      # @return [Integer]
      def hash
        options_hash.hash
      end

      # @param other [Object]
      # @return [Boolean]
      def eql?(other)
        return false unless other.is_a?(self.class)

        hash == other.hash
      end

      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        return false unless other.is_a?(self.class)

        options_hash == other.options_hash
      end
    end
  end
end
