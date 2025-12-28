# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class Multiple < AbstractCommand
      def call(&)
        queries.transactions.transaction(&)
      end
    end
  end
end
