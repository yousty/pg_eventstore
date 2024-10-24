# frozen_string_literal: true

module PgEventstore
  module CLI
    class SubscriptionOptions < BaseOptions
      option(
        :pid_path,
        metadata: Metadata.new(
          short: '-pFILE_PATH',
          long: '--pid=FILE_PATH',
          description: 'Defines pid file path. Defaults to /tmp/pg-es_subscriptions.pid'
        )
      ) do
        '/tmp/pg-es_subscriptions.pid'
      end

      # @param parser [OptionParser]
      # @return [void]
      def attach_parser_handlers(parser)
        %i[pid_path].each do |option|
          parser.on(*to_parser_opts(option)) do |value|
            public_send("#{option}=", value)
          end
        end
        super
      end
    end
  end
end
