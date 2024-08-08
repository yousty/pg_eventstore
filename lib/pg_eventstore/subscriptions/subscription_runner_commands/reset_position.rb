# frozen_string_literal: true

module PgEventstore
  module SubscriptionRunnerCommands
    # @!visibility private
    class ResetPosition < Base
      class << self
        # @param data [Hash]
        # @return [Hash]
        def parse_data(data)
          { 'position' => Integer(data['position']) }
        end
      end

      # @param subscription_runner [PgEventstore::SubscriptionRunner]
      # @return [void]
      def exec_cmd(subscription_runner)
        subscription_runner.within_state(:stopped) do
          subscription_runner.clear_chunk
          subscription_runner.subscription.update(
            last_chunk_greatest_position: nil, current_position: data['position'], total_processed_events: 0
          )
        end
      end
    end
  end
end
