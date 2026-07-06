# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class PgConnection < PG::Connection
    PLACEHOLDER_RE = /
      '(?:''|[^'])*'                                             | # string literal
      "(?:""|[^"])*"                                             | # quoted identifier
      --[^\n]*                                                   | # line comment
      \/\*.*?\*\/                                                | # block comment
      \$\$.*?\$\$                                                | # dollar-quoted string. E.g. $$ $1 $$
      \$(?<__dq_tag>[A-Za-z_][A-Za-z_0-9]*)\$.*?\$\k<__dq_tag>\$ | # named dollar-quoted string. E.g. $foo$ $1 $foo$
      (?<placeholder>\$(?:[1-9]\d*))                               # placeholder we are interested in
    /mx
    private_constant :PLACEHOLDER_RE

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

    # This is a partial copy-paste of https://github.com/ged/ruby-pg/pull/726. Because maintainers think it is too risky
    # to accept those changes because of possible sql injections in the long run - I copy-pasted it here and simplified
    # for pg_eventstore use cases.
    # Why is it safe for pg_eventstore? The main concern there is that if new string literal would be introduced in some
    # future PostgreSQL version - the implementation would become vulnerable to sql injections in case that new string
    # literal is used in queries along with #compile. Because pg_eventstore uses only two forms of string literals
    # (those are $$ my string $$ and 'my string') - we are totally safe. Also, there is only one place so far where this
    # method is used(create subscription table function) - all other places use exec/exec_params. To conclude: careful
    # usage + very low risk of future exposure to sql injections makes the usage of this method acceptable for
    # pg_eventstore.
    #
    # Compiles your prepared SQL statement and the given positional arguments into plain SQL string.
    #
    # The resulting SQL string can be used with +conn.exec+ like the prepared SQL statement and parameters with
    # +conn.exec_params+. +conn.exec_params+ is usually preferred because it's faster and safer.
    #
    # Example:
    # 	res = conn.compile('SELECT $1 AS a, $2 AS b, $3 AS c', [1, 2, nil])
    # 	# => "SELECT '1' AS a, '2' AS b, NULL AS c"
    # @param sql [String]
    # @param params [Array]
    # @return [String]
    def compile(sql, params)
      return sql if params.empty?

      sql.gsub(PLACEHOLDER_RE).each do |matched|
        placeholder = Regexp.last_match[:placeholder]
        # Do not replace non-positional args string and pass it as is
        next matched unless placeholder

        value = params[placeholder[1..].to_i - 1]
        value = encode_value(value)
        normalize_value(value)
      end
    end

    private

    def encode_value(value)
      unless type_map_for_queries.is_a?(PG::TypeMapByClass)
        raise <<~TEXT.strip
          Unsupported type map. Please use the one which is inherited from PG::TypeMapByClass, for example \
          PG::BasicTypeMapForQueries:
          conn = PG::Connection.new
          conn.type_map_for_queries = PG::BasicTypeMapForQueries.new(conn)
        TEXT
      end

      encoder = type_map_for_queries[value.class]
      return type_map_for_queries.send(encoder, value).encode(value) if encoder.is_a?(Symbol)
      # format == 1 stands for binary format
      return value if encoder.nil? || encoder.format == 1

      encoder.encode(value)
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

      PgEventstore.logger.debug(compile(sql, params))
    end
  end
end
