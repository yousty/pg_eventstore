# frozen_string_literal: true

module PgEventstore
  class Utils
    class << self
      # Deep transforms keys of a given Hash
      # @param object [Object]
      # @return [Object] a hash with transformed keys
      def deep_transform_keys(object, &block)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            result[yield(key)] = deep_transform_keys(value, &block)
          end
        when Array
          object.map { |e| deep_transform_keys(e, &block) }
        else
          object
        end
      end

      # Converts array to the string containing SQL positional variables
      # @param array [Array]
      # @return [String] positional variables, based on array size. Example: "$1, $2, $3"
      def positional_vars(array)
        array.size.times.map { |t| "$#{t + 1}" }.join(', ')
      end

      # Transforms exception instance into a hash
      # @param error [StandardError]
      # @return [Hash]
      def error_info(error)
        {
          class: error.class,
          message: error.message,
          backtrace: error.backtrace
        }
      end
    end
  end
end
