# frozen_string_literal: true

module EventHelpers
  # @param stream [PgEventstore::Stream]
  # @return [Array<PgEventstore::Event>]
  def safe_read(stream)
    PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { filter: { streams: [stream.to_hash] } })
  end
end
