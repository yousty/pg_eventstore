# frozen_string_literal: true

module PgEventstore
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

        value = type_map_for_queries[value.class]&.encode(value) || value
        value.is_a?(String) ? "'#{value}'" : value
      end unless params&.empty?
      PgEventstore.logger.debug(sql)
    end
  end
end
