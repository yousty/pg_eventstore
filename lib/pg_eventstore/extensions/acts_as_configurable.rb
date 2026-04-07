# frozen_string_literal: true

module PgEventstore
  module Extensions
    module ActsAsConfigurable
      # @param config_class [Class<PgEventstore:::BasicConfig>]
      # @param default_config [Symbol]
      # @return [void]
      def acts_as_configurable(config_class:, default_config: :default)
        const_set(:DEFAULT_CONFIG, default_config)
        const_set(:CONFIG_CLASS, config_class)
        extend Configurable
        init_variables
      end

      module Configurable
        # @!attribute mutex
        #   @return [Thread::Mutex]
        attr_reader :mutex
        private :mutex

        # Creates a Config if not exists and yields it to the given block.
        # @param name [Symbol] a name to assign to a config
        # @return [Object] a result of the given block
        def configure(name: const_get(:DEFAULT_CONFIG))
          config_class = const_get(:CONFIG_CLASS)
          mutex.synchronize do
            @config[name] = @config[name] ? config_class.new(name:, **@config[name].options_hash) : config_class.new(name:)
            connection_config_was = connection_options(@config[name])

            yield(@config[name]).tap do
              @config[name].freeze
              next if connection_config_was == connection_options(@config[name])

              # Reset the connection if user decided to reconfigure connection's options
              @connection.delete(name)
            end
          end
        end

        # @return [Array<Symbol>]
        def available_configs
          @config.keys
        end

        # @param name [Symbol]
        # @return [PgEventstore::Config]
        def config(name = const_get(:DEFAULT_CONFIG))
          return @config[name] if @config[name]

          error_message = <<~TEXT
            Could not find #{name.inspect} config. You can define it like this:
            #{self}.configure(name: #{name.inspect}) do |config|
              # your config goes here
            end
          TEXT
          raise error_message
        end

        # Look ups and returns a Connection, based on the given config. If not exists - it creates one. This operation
        # is a thread-safe
        # @param name [Symbol]
        # @return [PgEventstore::Connection]
        def connection(name = const_get(:DEFAULT_CONFIG))
          mutex.synchronize do
            @connection[name] ||= Connection.new(**connection_options(config(name)))
          end
        end

        private

        # @param config [PgEventstore::Extensions::OptionsExtension]
        # @return [Hash] { uri: String, pool_size: Integer, pool_timeout: Integer }
        def connection_options(config)
          raise NotImplementedError
        end

        # @return [void]
        def init_variables
          default_config = const_get(:DEFAULT_CONFIG)
          @config = { default_config => const_get(:CONFIG_CLASS).new(name: default_config) }
          @connection = {}
          @mutex = Thread::Mutex.new
        end
      end
    end
  end
end
