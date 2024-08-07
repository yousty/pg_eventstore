# frozen_string_literal: true

class DummyMiddleware
  include PgEventstore::Middleware

  ENCR_SECRET = 'secret'
  DECR_SECRET = '123456'

  # @param event [PgEventstore::Event]
  # @return [void]
  def serialize(event)
    event.metadata['dummy_secret'] = ENCR_SECRET
  end

  # @param event [PgEventstore::Event]
  # @return [void]
  def deserialize(event)
    event.metadata['dummy_secret'] = DECR_SECRET
  end
end

class Dummy2Middleware
  include PgEventstore::Middleware

  ENCR_SECRET = 'terces'
  DECR_SECRET = '654321'

  # @param event [PgEventstore::Event]
  # @return [void]
  def serialize(event)
    event.metadata['dummy2_secret'] = ENCR_SECRET
  end

  # @param event [PgEventstore::Event]
  # @return [void]
  def deserialize(event)
    event.metadata['dummy2_secret'] = DECR_SECRET
  end
end
