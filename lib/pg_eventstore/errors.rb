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
    attr_reader :stream

    # @param stream [PgEventstore::Stream]
    def initialize(stream)
      @stream = stream
      super("Stream #{stream.inspect} does not exist.")
    end
  end

  class SystemStreamError < Error
    attr_reader :stream

    # @param stream [PgEventstore::Stream]
    def initialize(stream)
      @stream = stream
      super("Stream #{stream.inspect} is a system stream and can't be used to append events.")
    end
  end

  class WrongExpectedRevisionError < Error
    attr_reader :stream, :revision, :expected_revision

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

  class RecordNotFound < Error
    attr_reader :table_name, :id

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
    attr_reader :set, :name, :lock_id

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
    attr_reader :set, :name, :lock_id

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
    attr_reader :stream, :event_types

    # @param stream [PgEventstore::Stream]
    # @param event_types [Array<String>]
    def initialize(stream, event_types)
      @stream = stream
      @event_types = event_types
    end
  end

  class EmptyChunkFedError < Error
  end
end
