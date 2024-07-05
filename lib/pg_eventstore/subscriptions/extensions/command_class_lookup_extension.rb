# frozen_string_literal: true

module PgEventstore
  module Extensions
    module CommandClassLookupExtension
      # @param cmd_name [String, Symbol]
      # @return [Class]
      def command_class(cmd_name)
        const_get(cmd_name, false)
      rescue NameError
        self::Base
      end
    end
  end
end
