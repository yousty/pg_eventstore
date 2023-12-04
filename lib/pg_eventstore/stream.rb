# frozen_string_literal: true

require 'digest/md5'

module PgEventstore
  class Stream
    class << self
      # Produces "all" stream instance. "all" stream does not represent any specific stream. Instead, it indicates that
      # a specific command should be performed over any kind of streams if possible
      # @return [PgEventstore::Stream]
      def all_stream
        allocate.tap do |stream|
          stream.instance_variable_set(:@all_stream, true)
        end
      end
    end

    attr_reader :context, :stream_name, :stream_id, :id

    # @param context [String]
    # @param stream_name [String]
    # @param stream_id [String]
    # @param id [Integer, nil] internal stream's id, read only
    def initialize(context:, stream_name:, stream_id:, id: nil)
      @context = context
      @stream_name = stream_name
      @stream_id = stream_id
      @id = id
    end

    # @return [Boolean]
    def all_stream?
      !!@all_stream
    end

    # @return [Array]
    def deconstruct
      [context, stream_name, stream_id]
    end
    alias to_a deconstruct

    # @param keys [Array<Symbol>, nil]
    def deconstruct_keys(keys)
      hash = { context: context, stream_name: stream_name, stream_id: stream_id }
      return hash unless keys

      hash.slice(*keys)
    end

    # @return [Hash]
    def to_hash
      deconstruct_keys(nil)
    end

    def ==(other_stream)
      return false unless other_stream.is_a?(Stream)

      to_hash == other_stream.to_hash
    end
  end
end
