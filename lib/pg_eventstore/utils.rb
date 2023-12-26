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
    end
  end
end
