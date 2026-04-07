# frozen_string_literal: true

module PgEventstore
  class BasicConfig
    include Extensions::OptionsExtension

    attr_reader :name

    # @param name [Symbol] config's name. Its value matches the appropriate key in PgEventstore.config hash
    def initialize(name:, **)
      super
      @name = name
    end
  end
end
