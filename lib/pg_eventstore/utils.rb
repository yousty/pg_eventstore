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

      # Deep dup Array or Hash
      # @param object [Object]
      # @return [Object]
      def deep_dup(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            result[deep_dup(key)] = deep_dup(value)
          end
        when Array
          object.map { |e| deep_dup(e) }
        else
          object.dup
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

      # @param str [String]
      # @return [String]
      def underscore_str(str)
        str = str.dup
        str[0] = str[0].downcase
        str.gsub!(/[A-Z]/) { |letter| '_' + letter.downcase }
        str
      end

      # Detect the global position of the event record in the database. If it is a link event - we pick a
      # global_position of the link instead of picking a global_position of an event this link points to.
      # @param raw_event [Hash]
      # @return [Integer]
      def original_global_position(raw_event)
        raw_event['link'] ? raw_event['link']['global_position'] : raw_event['global_position']
      end
    end
  end
end
