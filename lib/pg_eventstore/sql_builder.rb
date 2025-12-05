# frozen_string_literal: true

module PgEventstore
  # Deadly simple SQL builder
  # @!visibility private
  class SQLBuilder
    class << self
      # @param builders [Array<PgEventstore::SQLBuilder>]
      # @return [PgEventstore::SQLBuilder]
      def union_builders(builders)
        builders[1..].each_with_object(builders[0]) do |builder, first_builder|
          first_builder.union(builder)
        end
      end
    end

    # @return [Array<Object>] sql positional values
    attr_reader :positional_values
    # @return [Integer]
    attr_writer :positional_values_size

    protected :positional_values, :positional_values_size=

    def initialize
      @select_values = []
      @from_value = nil
      @where_values = { 'AND' => [], 'OR' => [] }
      @join_values = []
      @group_values = []
      @order_values = []
      @limit_value = nil
      @offset_value = nil
      @positional_values = []
      @positional_values_size = 0
      @union_values = []
    end

    # @param sql [String]
    # @return [self]
    def select(sql)
      @select_values.push(sql)
      self
    end

    # @return [self]
    def unselect
      @select_values.clear
      self
    end

    # @param sql [String]
    # @param arguments [Array] positional values
    # @return [self]
    def where(sql, *arguments)
      @where_values['AND'].push([sql, arguments])
      self
    end

    # @param sql [String]
    # @param arguments [Object] positional values
    # @return [self]
    def where_or(sql, *arguments)
      @where_values['OR'].push([sql, arguments])
      self
    end

    # @param table_name [String | SQLBuilder]
    # @return [self]
    def from(table_name)
      @from_value = table_name
      self
    end

    # @param sql [String]
    # @param arguments [Object]
    # @return [self]
    def join(sql, *arguments)
      @join_values.push([sql, arguments])
      self
    end

    # @param sql [String]
    # @return [self]
    def order(sql)
      @order_values.push(sql)
      self
    end

    # @return [self]
    def remove_order
      @order_values.clear
      self
    end

    # @param limit [Integer]
    # @return [self]
    def limit(limit)
      @limit_value = limit.to_i
      self
    end

    # @return [self]
    def remove_limit
      @limit_value = nil
      self
    end

    # @param offset [Integer]
    # @return [self]
    def offset(offset)
      @offset_value = offset.to_i
      self
    end

    # @param another_builder [PgEventstore::SQLBuilder]
    # @return [self]
    def union(another_builder)
      @union_values.push(another_builder)
      self
    end

    # @param sql [String]
    # @return [self]
    def group(sql)
      @group_values.push(sql)
      self
    end

    # @return [self]
    def remove_group
      @group_values.clear
      self
    end

    # @return [[String, Array<_>]]
    def to_exec_params
      @positional_values.clear
      @positional_values_size = 0
      _to_exec_params
    end

    protected

    # @return [[String, Array<_>]]
    def _to_exec_params
      return [single_query_sql, @positional_values] if @union_values.empty?

      [union_query_sql, @positional_values]
    end

    # @return [String]
    def from_sql
      return @from_value if @from_value.is_a?(String)

      sql = merge(@from_value)
      "(#{sql}) #{@from_value.from_sql}"
    end

    private

    # @return [String]
    def single_query_sql
      where_sql = [where_sql('OR'), where_sql('AND')].reject(&:empty?).map { |sql| "(#{sql})" }.join(' AND ')
      sql = "SELECT #{select_sql} FROM #{from_sql}"
      sql += " #{join_sql}" unless @join_values.empty?
      sql += " WHERE #{where_sql}" unless where_sql.empty?
      sql += " GROUP BY #{@group_values.join(', ')}" unless @group_values.empty?
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
        "(#{merge(builder)})"
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
      @join_values.map { |sql, args| extract_positional_args(sql, *args) }.join(' ')
    end

    # @return [String]
    def order_sql
      @order_values.join(', ')
    end

    # @param builder [PgEventstore::SQLBuilder]
    # @return [String]
    def merge(builder)
      builder.positional_values_size = @positional_values_size
      sql_query, positional_values = builder._to_exec_params
      @positional_values.push(*positional_values)
      @positional_values_size += positional_values.size
      sql_query
    end

    # Replaces "?" signs in the given string with positional variables and memorize positional values they refer to.
    # @param sql [String]
    # @return [String]
    def extract_positional_args(sql, *arguments)
      sql.gsub('?').each_with_index do |_, index|
        if arguments[index].is_a?(SQLBuilder)
          "(#{merge(arguments[index])})"
        else
          @positional_values.push(arguments[index])
          @positional_values_size += 1
          "$#{@positional_values_size}"
        end
      end
    end
  end
end
