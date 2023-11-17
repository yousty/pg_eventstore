# frozen_string_literal: true

require 'digest/md5'

module PgEventstore
  class Stream
    BIGINT = -9223372036854775808..9223372036854775807
    ALL_STREAM = "$all"

    class << self
      # @return [PgEventstore::Stream]
      def all_stream
        new(context: ALL_STREAM, stream_name: nil, stream_id: nil)
      end
    end

    attr_reader :context, :stream_name, :stream_id

    # @param context [String]
    # @param stream_name [String]
    # @param stream_id [String]
    def initialize(context:, stream_name:, stream_id:)
      @context = context
      @stream_name = stream_name
      @stream_id = stream_id
    end

    # @return [Boolean]
    def all?
      context == ALL_STREAM
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

    # Calculate pg's bigint value to be used in the lock function.
    # @return [Integer]
    def lock_id
      ubigint = Digest::MD5.hexdigest("#{context}::#{stream_name}$#{stream_id}")[0..15].to_i(16)
      return ubigint if ubigint <= BIGINT.end

      BIGINT.end - ubigint
    end
  end
end
