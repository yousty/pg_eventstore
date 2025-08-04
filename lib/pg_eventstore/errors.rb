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
    # @!attribute stream
    #   @return [PgEventstore::Stream]
    attr_reader :stream

    # @param stream [PgEventstore::Stream]
    def initialize(stream)
      @stream = stream
      super("Stream #{stream.inspect} does not exist.")
    end
  end

  class SystemStreamError < Error
    # @!attribute stream
    #   @return [PgEventstore::Stream]
    attr_reader :stream

    # @param stream [PgEventstore::Stream]
    def initialize(stream)
      @stream = stream
      super("Can't perform this action with #{stream.inspect} system stream.")
    end
  end

  class WrongExpectedRevisionError < Error
    # @!attribute stream
    #   @return [PgEventstore::Stream]
    attr_reader :stream
    # @!attribute revision
    #   @return [Integer]
    attr_reader :revision
    # @!attribute expected_revision
    #   @return [Integer, Symbol]
    attr_reader :expected_revision

    # @param revision [Integer]
    # @param expected_revision [Integer, Symbol]
    # @param stream [PgEventstore::Stream]
    def initialize(revision:, expected_revision:, stream:)
      @revision = revision
      @expected_revision = expected_revision
      @stream = stream
      super(user_friendly_message)
    end

    private

    # @return [String]
    def user_friendly_message
      if revision == Stream::NON_EXISTING_STREAM_REVISION && expected_revision == :stream_exists
        return expected_stream_exists
      end
      return expected_no_stream if revision > Stream::NON_EXISTING_STREAM_REVISION && expected_revision == :no_stream
      return current_no_stream if revision == Stream::NON_EXISTING_STREAM_REVISION && expected_revision.is_a?(Integer)

      unmatched_stream_revision
    end

    # @return [String]
    def expected_stream_exists
      "Expected stream #{stream_descr} to exist, but it doesn't."
    end

    # @return [String]
    def expected_no_stream
      "Expected stream #{stream_descr} to be absent, but it actually exists."
    end

    # @return [String]
    def current_no_stream
      "#{stream_descr} stream revision #{expected_revision.inspect} is expected, but stream does not exist."
    end

    # @return [String]
    def unmatched_stream_revision
      <<~TEXT.strip
        #{stream_descr} stream revision #{expected_revision.inspect} is expected, but actual stream revision is \
        #{revision.inspect}.
      TEXT
    end

    # @return [String]
    def stream_descr
      stream.to_hash.inspect
    end
  end

  class RecordNotFound < Error
    # @!attribute table_name
    #   @return [String]
    attr_reader :table_name
    # @!attribute id
    #   @return [Integer, String]
    attr_reader :id

    # @param table_name [String]
    # @param id [Integer, String]
    def initialize(table_name, id)
      @table_name = table_name
      @id = id
      super(user_friendly_message)
    end

    # @return [String]
    def user_friendly_message
      "Could not find/update #{table_name.inspect} record with #{id.inspect} id."
    end
  end

  class SubscriptionAlreadyLockedError < Error
    # @!attribute set
    #   @return [String]
    attr_reader :set
    # @!attribute name
    #   @return [String]
    attr_reader :name
    # @!attribute lock_id
    #   @return [Integer]
    attr_reader :lock_id

    # @param set [String] subscriptions set name
    # @param name [String] subscription's name
    # @param lock_id [Integer]
    def initialize(set, name, lock_id)
      @set = set
      @name = name
      @lock_id = lock_id
      super(user_friendly_message)
    end

    # @return [String]
    def user_friendly_message
      <<~TEXT.strip
        Could not lock subscription from #{set.inspect} set with #{name.inspect} name. It is already locked by \
        ##{lock_id.inspect} set.
      TEXT
    end
  end

  class WrongLockIdError < Error
    # @!attribute set
    #   @return [String]
    attr_reader :set
    # @!attribute name
    #   @return [String]
    attr_reader :name
    # @!attribute lock_id
    #   @return [Integer]
    attr_reader :lock_id

    # @param set [String] subscriptions set name
    # @param name [String] subscription's name
    # @param lock_id [Integer]
    def initialize(set, name, lock_id)
      @set = set
      @name = name
      @lock_id = lock_id
      super(user_friendly_message)
    end

    # @return [String]
    def user_friendly_message
      <<~TEXT.strip
        Could not update subscription from #{set.inspect} set with #{name.inspect} name. It is locked by \
        ##{lock_id.inspect} set suddenly.
      TEXT
    end
  end

  class NotPersistedEventError < Error
    # @!attribute event
    #   @return [PgEventstore::Event]
    attr_reader :event

    # @param event [PgEventstore::Event]
    def initialize(event)
      @event = event
      super(user_friendly_message)
    end

    # @return [String]
    def user_friendly_message
      "Event with #id #{event.id.inspect} must be present, but it could not be found."
    end
  end

  class MissingPartitions < Error
    # @!attribute stream
    #   @return [PgEventstore::Stream]
    attr_reader :stream
    # @!attribute event_types
    #   @return [Array<String>]
    attr_reader :event_types

    # @param stream [PgEventstore::Stream]
    # @param event_types [Array<String>]
    def initialize(stream, event_types)
      @stream = stream
      @event_types = event_types
      super("Missing partitions for stream #{stream.inspect}, event types #{event_types.inspect}")
    end
  end

  class EmptyChunkFedError < Error
  end

  class TooManyRecordsToLockError < Error
    attr_reader :stream
    attr_reader :number_of_records

    # @param stream [PgEventstore::Stream]
    # @param number_of_records [Integer]
    def initialize(stream, number_of_records)
      @stream = stream
      @number_of_records = number_of_records
      super(user_friendly_message)
    end

    # @return [String]
    def user_friendly_message
      "Too many records of #{stream.to_hash.inspect} stream to lock: #{number_of_records}"
    end
  end

  class WrappedException < StandardError
    attr_reader :original_exception
    attr_reader :extra

    def initialize(original_exception, extra)
      @original_exception = original_exception
      @extra = extra
      super()
    end
  end
end
