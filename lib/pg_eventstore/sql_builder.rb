# frozen_string_literal: true

module PgEventstore
  # Deadly simple SQL builder
  # @!visibility private
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
      @positional_values_size = 0
      @union_values = []
    end

    # @param sql [String]
    # @return self
    def select(sql)
      @select_values.push(sql)
      self
    end

    # @return self
    def unselect
      @select_values.clear
      self
    end

    # @param sql [String]
    # @param arguments [Array] positional values
    # @return self
    def where(sql, *arguments)
      @where_values['AND'].push([sql, arguments])
      self
    end

    # @param sql [String]
    # @param arguments [Object] positional values
    # @return self
    def where_or(sql, *arguments)
      @where_values['OR'].push([sql, arguments])
      self
    end

    # @param table_name [String]
    # @return self
    def from(table_name)
      @from_value = table_name
      self
    end

    # @param sql [String]
    # @param arguments [Object]
    # @return self
    def join(sql, *arguments)
      @join_values.push([sql, arguments])
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

    def union(another_builder)
      @union_values.push(another_builder)
      self
    end

    def to_exec_params
      return [single_query_sql, @positional_values] if @union_values.empty?

      [union_query_sql, @positional_values]
    end

    protected

    def positional_values
      @positional_values
    end

    def positional_values_size=(val)
      @positional_values_size = val
    end

    private

    # @return [String]
    def single_query_sql
      where_sql = [where_sql('OR'), where_sql('AND')].reject(&:empty?).map { |sql| "(#{sql})" }.join(' AND ')
      sql = "SELECT #{select_sql} FROM #{@from_value}"
      sql += " #{join_sql}" unless @join_values.empty?
      sql += " WHERE #{where_sql}" unless where_sql.empty?
      sql += " ORDER BY #{order_sql}" unless @order_values.empty?
      sql += " LIMIT #{@limit_value}" if @limit_value
      sql += " OFFSET #{@offset_value}" if @offset_value
      sql
    end

    # @return [String]
    def union_query_sql
      sql = single_query_sql
      union_parts = ["(#{sql})"]
      union_parts += @union_values.map do |builder|
        builder.positional_values_size = @positional_values_size
        builder_sql, values = builder.to_exec_params
        @positional_values.push(*values)
        @positional_values_size += values.size
        "(#{builder_sql})"
      end
      union_parts.join(' UNION ALL ')
    end

    # @return [String]
    def select_sql
      @select_values.empty? ? '*' : @select_values.join(', ')
    end

    # @param join_pattern [String] "OR"/"AND"
    # @return [String]
    def where_sql(join_pattern)
      @where_values[join_pattern].map do |sql, args|
        "(#{extract_positional_args(sql, *args)})"
      end.join(" #{join_pattern} ")
    end

    # @return [String]
    def join_sql
      @join_values.map { |sql, args| extract_positional_args(sql, *args) }.join(" ")
    end

    # @return [String]
    def order_sql
      @order_values.join(', ')
    end

    def extract_positional_args(sql, *arguments)
      sql.gsub("?").each_with_index do |_, index|
        @positional_values.push(arguments[index])
        @positional_values_size += 1
        "$#{@positional_values_size}"
      end
    end
  end
end
