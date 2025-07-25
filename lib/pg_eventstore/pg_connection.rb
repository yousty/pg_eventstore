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

    private

    def log(sql, params)
      return unless PgEventstore.logger&.debug?

      sql = sql.gsub(/\$\d+/).each do |matched|
        value = params[matched[1..].to_i - 1]
        value = encode_value(value)
        normalize_value(value)
      end unless params&.empty?
      PgEventstore.logger.debug(sql)
    end

    def encode_value(value)
      encoder = type_map_for_queries[value.class]
      return type_map_for_queries.send(encoder, value).encode(value) if encoder.is_a?(Symbol)

      type_map_for_queries[value.class]&.encode(value) || value
    end

    def normalize_value(value)
      case value
      when String
        "'#{value}'"
      when NilClass
        'NULL'
      else
        value
      end
    end
  end
end
