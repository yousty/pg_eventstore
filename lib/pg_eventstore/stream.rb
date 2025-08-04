# frozen_string_literal: true

require 'digest/md5'

module PgEventstore
  class Stream
    # @return [String] a stream prefix of the system stream
    SYSTEM_STREAM_PREFIX = '$'
    # @return [Integer]
    NON_EXISTING_STREAM_REVISION = -1
    # @return [Array<String>]
    KNOWN_SYSTEM_STREAMS = %w[$streams].freeze

    class << self
      # Produces "all" stream instance. "all" stream does not represent any specific stream. Instead, it indicates that
      # a specific command should be performed over any kind of streams if possible
      # @return [PgEventstore::Stream]
      def all_stream
        allocate.tap do |stream|
          stream.instance_variable_set(:@all_stream, true)
        end
      end

      # @param name [String]
      # @return [PgEventstore::Stream]
      def system_stream(name)
        new(context: name, stream_name: '', stream_id: '')
      end
    end

    # @!attribute context
    #   @return [String]
    attr_reader :context
    # @!attribute stream_name
    #   @return [String]
    attr_reader :stream_name
    # @!attribute stream_id
    #   @return [String]
    attr_reader :stream_id

    # @param context [String]
    # @param stream_name [String]
    # @param stream_id [String]
    def initialize(context:, stream_name:, stream_id:)
      @context = context
      @stream_name = stream_name
      @stream_id = stream_id
    end

    # @return [Boolean]
    def all_stream?
      !!@all_stream
    end

    # Determine whether a stream is reserved by `pg_eventstore`. You can't append events to such streams.
    # @return [Boolean]
    def system?
      all_stream? || context.start_with?(SYSTEM_STREAM_PREFIX)
    end

    # @return [Array]
    def deconstruct
      [context, stream_name, stream_id]
    end
    alias to_a deconstruct

    # @param keys [Array<Symbol>, nil]
    # @return [Hash<Symbol => String>]
    def deconstruct_keys(keys)
      hash = { context: context, stream_name: stream_name, stream_id: stream_id }
      return hash unless keys

      hash.slice(*keys)
    end

    # @return [Hash]
    def to_hash
      deconstruct_keys(nil)
    end

    # @return [Integer]
    def hash
      to_hash.hash
    end

    # @param other [Object]
    # @return [Boolean]
    def eql?(other)
      return false unless other.is_a?(Stream)

      hash == other.hash
    end

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(Stream)

      to_hash == other.to_hash
    end
  end
end
