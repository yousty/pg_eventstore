# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class Multiple < AbstractCommand
      def call(read_only:, &blk)
        queries.transactions.transaction(read_only: read_only, &blk)
      end
    end
  end
end
