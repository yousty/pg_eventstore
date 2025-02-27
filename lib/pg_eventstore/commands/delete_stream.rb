# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class DeleteStream < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @return [Boolean]
      def call(stream)
        raise SystemStreamError, stream if stream.system?

        queries.transactions.transaction do
          queries.maintenance.delete_stream(stream) > 0
        end
      end
    end
  end
end
