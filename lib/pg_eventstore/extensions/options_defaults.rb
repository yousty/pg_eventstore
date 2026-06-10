# frozen_string_literal: true

module PgEventstore
  module Extensions
    # @!visibility private
    module OptionsDefaults
      def ==(other)
        return false unless other.is_a?(self.class)

        attributes_hash == other.attributes_hash
      end
      alias eql? ==

      # @return [Integer]
      def hash
        attributes_hash.hash
      end

      # @return [self]
      def dup
        self.class.new(**Utils.deep_dup(options_hash))
      end
    end
  end
end
