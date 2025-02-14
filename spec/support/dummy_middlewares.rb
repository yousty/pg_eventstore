# frozen_string_literal: true

class DummyMiddleware
  include PgEventstore::Middleware

  ENCR_SECRET = 'secret'
  DECR_SECRET = '123456'
  STORAGE_KEY = 'dummy_secret'

  # @param event [PgEventstore::Event]
  # @return [void]
  def serialize(event)
    event.metadata[STORAGE_KEY] = ENCR_SECRET
  end

  # @param event [PgEventstore::Event]
  # @return [void]
  def deserialize(event)
    event.metadata[STORAGE_KEY] = DECR_SECRET
  end
end

class Dummy2Middleware
  include PgEventstore::Middleware

  ENCR_SECRET = 'terces'
  DECR_SECRET = '654321'
  STORAGE_KEY = 'dummy2_secret'

  # @param event [PgEventstore::Event]
  # @return [void]
  def serialize(event)
    event.metadata[STORAGE_KEY] = ENCR_SECRET
  end

  # @param event [PgEventstore::Event]
  # @return [void]
  def deserialize(event)
    event.metadata[STORAGE_KEY] = DECR_SECRET
  end
end
