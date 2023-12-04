# frozen_string_literal: true

module PgEventstore
  # Deadly simple SQL builder
  class SQLBuilder
    def initialize
      @select_values = []
      @from_value = nil
      @where_values = { 'AND' => [], 'OR' => [] }
      @join_values = []
      @order_values = []
      @limit_value = nil
      @offset_value = nil
      @positional_values = []
    end

    # @param sql [String]
    # @return self
    def select(sql)
      @select_values.push(sql)
      self
    end

    def unselect
      @select_values.clear
      self
    end

    # @param sql [String]
    # @param arguments [Array] positional values
    # @return self
    def where(sql, *arguments)
      _where(sql, 'AND', *arguments)
      self
    end

    # @param sql [String]
    # @param arguments [Object] positional values
    # @return self
    def where_or(sql, *arguments)
      _where(sql, 'OR', *arguments)
      self
    end

    # @param table_name [String]
    # @return self
    def from(table_name)
      @from_value = table_name
      self
    end

    # @param sql [String]
    # @return self
    def join(sql)
      @join_values.push(sql)
      self
    end

    # @param sql [String]
    # @return self
    def order(sql)
      @order_values.push(sql)
      self
    end

    # @param limit [Integer]
    # @return self
    def limit(limit)
      @limit_value = limit.to_i
      self
    end

    # @param offset [Integer]
    # @return self
    def offset(offset)
      @offset_value = offset.to_i
      self
    end

    def to_exec_params
      where_sql = [where_sql('OR'), where_sql('AND')].reject(&:empty?).map { |sql| "(#{sql})" }.join(' AND ')
      sql = "SELECT #{select_sql} FROM #{@from_value}"
      sql += " #{join_sql}" unless @join_values.empty?
      sql += " WHERE #{where_sql}" unless where_sql.empty?
      sql += " ORDER BY #{order_sql}" unless @order_values.empty?
      sql += " LIMIT #{@limit_value}" if @limit_value
      sql += " OFFSET #{@offset_value}" if @offset_value
      [sql, @positional_values]
    end

    private

    # @param sql [String]
    # @param join_pattern [String] determines how to join where value - either using AND or using OR
    # @param arguments [Array] positional values
    # @return [void]
    def _where(sql, join_pattern, *arguments)
      sql = sql.gsub("?").each_with_index do |_, index|
        @positional_values.push(arguments[index])
        "$#{@positional_values.size}"
      end
      @where_values[join_pattern].push("(#{sql})")
    end

    # @return [String]
    def select_sql
      @select_values.empty? ? '*' : @select_values.join(',')
    end

    # @param join_pattern [String] "OR"/"AND"
    # @return [String]
    def where_sql(join_pattern)
      @where_values[join_pattern].join(" #{join_pattern} ")
    end

    # @return [String]
    def join_sql
      @join_values.join(" ")
    end

    # @return [String]
    def order_sql
      @order_values.join(', ')
    end
  end
end
