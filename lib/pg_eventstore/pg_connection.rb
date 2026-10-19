# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class PgConnection < PG::Connection
    def exec(sql)
      log(sql, [])
      super
    end

    def exec_params(sql, params, ...)
      log(sql, params)
      super
    end

    def send_query_params(sql, params)
      log(sql, params)
      super
    end

    def send_query(sql)
      log(sql, [])
      super
    end

    # Converts the given object into its PostgreSQL representation
    def prepared_value(value)
      value = encode_value(value)
      normalize_value(value)
    end

    private

    def encode_value(value)
      encoder = type_map_for_queries.query_param_encoders([value]).first
      # format == 1 stands for binary format
      return encoder.encode(value) if encoder && encoder.format == 0

      value
    end

    def normalize_value(value)
      case value
      when TrueClass, FalseClass
        value.to_s
      when NilClass
        'NULL'
      else
        "'#{escape(value.to_s)}'"
      end
    end

    def log(sql, params)
      return unless PgEventstore.logger&.debug?

      PgEventstore.logger.debug(embed_params(sql, params))
    end
  end
end
