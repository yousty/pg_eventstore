# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class Multiple < AbstractCommand
      def call(read_only:, &)
        queries.transactions.transaction(read_only:, &)
      end
    end
  end
end
