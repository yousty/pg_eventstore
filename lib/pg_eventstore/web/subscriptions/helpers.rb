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

        # @param state [String]
        # @return [String]
        def subscriptions_state_url(state:, **params)
          params = params.compact
          return url("/subscriptions/#{state}") if params.empty?

          encoded_params = Rack::Utils.build_nested_query(params)
          url("/subscriptions/#{state}?#{encoded_params}")
        end

        # @return [String, nil]
        def subscriptions_state
          params[:state] if PgEventstore::RunnerState::STATES.values.include?(params[:state])
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

        # @param cmd_name [String] command name
        # @return [String] command name
        def subscriptions_set_cmd(cmd_name)
          validate_subscriptions_set_cmd(cmd_name)

          cmd_name
        end

        # @param cmd_name [String]
        # @return [void]
        # @raise [RuntimeError] in case if command class is not found
        def validate_subscriptions_set_cmd(cmd_name)
          cmd_class = SubscriptionFeederCommands.command_class(cmd_name)
          raise "SubscriptionsSet command #{cmd_name.inspect} does not exist" unless cmd_class.known_command?
        end

        # @param cmd_name [String] command name
        # @return [String] command name
        def subscription_cmd(cmd_name)
          validate_subscription_cmd(cmd_name)

          cmd_name
        end

        # @param cmd_name [String]
        # @return [void]
        # @raise [RuntimeError] in case if command class is not found
        def validate_subscription_cmd(cmd_name)
          cmd_class = SubscriptionRunnerCommands.command_class(cmd_name)
          raise "Subscription command #{cmd_name.inspect} does not exist" unless cmd_class.known_command?
        end

        # @param state [String]
        # @param updated_at [Time]
        # @return [String] html status
        def colored_state(state, interval, updated_at)
          text_class =
            case state
            when RunnerState::STATES[:running]
              alive?(interval, updated_at) ? 'text-success' : 'text-warning'
            when RunnerState::STATES[:dead]
              'text-danger'
            else
              'text-info'
            end

          if alive?(interval, updated_at)
            <<~HTML
              <span class="#{text_class}">#{state}</span>
            HTML
          else
            title = <<~TEXT
              Something is wrong. Last update was more than #{interval} seconds ago(#{updated_at}).
            TEXT
            <<~HTML
              <span class="#{text_class} text-nowrap">
                #{state}
                <i class="fa fa-question-circle" data-toggle="tooltip" title="#{title}"></i>
              </span>
            HTML
          end
        end

        # @param interval [Integer]
        # @param last_updated_at [Time]
        # @return [Boolean]
        def alive?(interval, last_updated_at)
          # -1 is added as a margin to prevent false-positive result
          last_updated_at > Time.now.utc - interval - 1
        end

        # @param ids [Array<Integer>]
        # @return [String]
        def delete_all_subscriptions_url(ids)
          encoded_params = Rack::Utils.build_nested_query(ids: ids)
          url("/delete_all_subscriptions?#{encoded_params}")
        end

        # @param global_position [Integer]
        # @return [String]
        def delete_event_url(global_position)
          url("/delete_event/#{global_position}")
        end

        # @param stream_attrs [Hash]
        # @return [String]
        def delete_stream_url(stream_attrs)
          encoded_params = Rack::Utils.build_nested_query(stream_attrs)
          url("/delete_stream?#{encoded_params}")
        end
      end
    end
  end
end
