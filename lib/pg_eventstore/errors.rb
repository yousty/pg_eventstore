# frozen_string_literal: true

module PgEventstore
  class Error < StandardError
    # @return [Hash]
    def as_json(*)
      to_h.transform_keys(&:to_s)
    end

    # @return [Hash]
    def to_h
      hash =
        instance_variables.each_with_object({}) do |var, result|
          key = var.to_s
          key[0] = '' # remove @ sign
          result[key.to_sym] = instance_variable_get(var)
        end
      hash[:message] = message
      hash[:backtrace] = backtrace
      hash
    end
  end

  class StreamNotFoundError < Error
    attr_reader :stream_name

    # @param stream_name [String]
    def initialize(stream_name)
      @stream_name = stream_name
      super("Stream #{stream_name.inspect} does not exist.")
    end
  end

  class WrongExpectedVersionError < Error
    attr_reader :revision, :expected_revision

    # @param revision [Integer]
    # @param expected_revision [Integer, Symbol]
    def initialize(revision, expected_revision)
      @revision = revision
      @expected_revision = expected_revision
      super(user_friendly_message)
    end

    private

    # @return [String]
    def user_friendly_message
      return expected_stream_exists if revision == -1 && expected_revision == :stream_exists
      return expected_no_stream if revision > -1 && expected_revision == :no_stream
      return current_no_stream if revision == -1 && expected_revision.is_a?(Integer)

      unmatched_stream_revision
    end

    # @return [String]
    def expected_stream_exists
      "Expected stream to exist, but it doesn't."
    end

    # @return [String]
    def expected_no_stream
      "Expected stream to be absent, but it actually exists."
    end

    # @return [String]
    def current_no_stream
      "Stream revision #{expected_revision} is expected, but stream does not exist."
    end

    # @return [String]
    def unmatched_stream_revision
      "Stream revision #{expected_revision} is expected, but actual stream revision is #{revision.inspect}."
    end
  end

  class StreamDeletionError < Error
    attr_reader :stream_name, :details

    # @param stream_name [String]
    # @param details [String]
    def initialize(stream_name, details:)
      @stream_name = stream_name
      @details = details
      super(user_friendly_message)
    end

    # @return [String]
    def user_friendly_message
      <<~TEXT.strip
        Could not delete #{stream_name.inspect} stream. It seems that a stream with that \
        name does not exist, has already been deleted or its state does not match the \
        provided :expected_revision option. Please check #details for more info.
      TEXT
    end
  end
end
