# frozen_string_literal: true

module EventHelpers
  UUID_REGEXP = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\z/i
  # @param stream [PgEventstore::Stream]
  # @return [Array<PgEventstore::Event>]
  def safe_read(stream)
    PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { streams: [stream.to_hash] } })
  end
end
