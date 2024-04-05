# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      module Helpers
        # @param set_name [String, nil]
        # @return [String]
        def subscriptions_url(set_name: nil)
          return url('/subscriptions') unless set_name

          encoded_params = Rack::Utils.build_nested_query(set_name: set_name)
          url("/subscriptions?#{encoded_params}")
        end

        # @param set_id [Integer]
        # @param id [Integer]
        # @param cmd [String]
        # @return [String]
        def subscription_cmd_url(set_id, id, cmd)
          url("/subscription_cmd/#{set_id}/#{id}/#{cmd}")
        end

        # @param id [Integer]
        # @param cmd [String]
        # @return [String]
        def subscriptions_set_cmd_url(id, cmd)
          url("/subscriptions_set_cmd/#{id}/#{cmd}")
        end

        # @return [Hash{Symbol => String}]
        def subscriptions_set_cmds
          CommandHandlers::SubscriptionFeederCommands::AVAILABLE_COMMANDS
        end

        # @return [Hash{Symbol => String}]
        def subscriptions_cmds
          CommandHandlers::SubscriptionRunnersCommands::AVAILABLE_COMMANDS
        end

        # @param state [String]
        # @param updated_at [Time]
        # @return [String] html status
        def colored_state(state, updated_at)
          if state == RunnerState::STATES[:running]
            if updated_at < Time.now.utc - SubscriptionFeeder::HEARTBEAT_INTERVAL
              title = <<~TEXT
                Something is wrong. Last update was more than #{SubscriptionFeeder::HEARTBEAT_INTERVAL} seconds \
                ago(#{updated_at}).
              TEXT
              <<~HTML
                <span class="text-warning text-nowrap">
                  #{state}
                  <i class="fa fa-question-circle" data-toggle="tooltip" title="#{title}"></i>
                </span>              
              HTML
            else
              "<span class=\"text-success\">#{state}</span>"
            end
          elsif state == RunnerState::STATES[:dead]
            "<span class=\"text-danger\">#{state}</span>"
          else
            "<span class=\"text-info\">#{state}</span>"
          end
        end

        # @param ids [Array<Integer>]
        # @return [String]
        def delete_all_subscriptions_url(ids)
          encoded_params = Rack::Utils.build_nested_query(ids: ids)
          url("/delete_all_subscriptions?#{encoded_params}")
        end
      end
    end
  end
end
