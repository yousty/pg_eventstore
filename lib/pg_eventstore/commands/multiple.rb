# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class Multiple < AbstractCommand
      def call(&blk)
        queries.transactions.transaction do
          yield
        end
      end
    end
  end
end
