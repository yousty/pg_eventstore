# frozen_string_literal: true

require 'securerandom'
require 'base64'

module PgEventstore
  module Web
    class Application < Sinatra::Base
      # @return [Symbol]
      DEFAULT_ADMIN_UI_CONFIG = :admin_web_ui
      # @return [String]
      COOKIES_CONFIG_KEY = 'current_config'
      # @return [String]
      COOKIES_FLASH_MESSAGE_KEY = 'flash_message'

      set :static_cache_control, [:private, max_age: 86400]
      set :environment, -> { (ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV['APP_ENV'])&.to_sym || :development }
      set :logging, -> { environment == :development || environment == :test }
      set :erb, layout: :'layouts/application'
      set :host_authorization, { allow_if: ->(_env) { true } }

      helpers(Paginator::Helpers, Subscriptions::Helpers) do
        # @return [Array<Hash>, nil]
        def streams_filter
          params in { filter: { streams: Array => streams } }
          streams&.select { _1 in { context: String, stream_name: String, stream_id: String } }&.map do
            Hash[_1.reject { |_, value| value == '' }].transform_keys(&:to_sym)
          end&.reject { _1.empty? }
        end

        # @return [String, nil]
        def system_stream
          params in { filter: { system_stream: String => system_stream } }
          system_stream if Stream::KNOWN_SYSTEM_STREAMS.include?(system_stream)
        end

        # @return [Array<String>, nil]
        def events_filter
          params in { filter: { events: Array => events } }
          events&.select { _1.is_a?(String) && _1 != '' }
        end

        # @return [Symbol]
        def current_config
          resolve_config_by_name(request.cookies[COOKIES_CONFIG_KEY]&.to_s&.to_sym)
        end

        # @param config_name [Symbol, nil]
        # @return [Symbol]
        def resolve_config_by_name(config_name)
          existing_config = [config_name, DEFAULT_ADMIN_UI_CONFIG].find do |name|
            PgEventstore.available_configs.include?(name)
          end

          existing_config || PgEventstore::DEFAULT_CONFIG
        end

        # @param val [Object]
        # @return [void]
        def current_config=(val)
          response.set_cookie(COOKIES_CONFIG_KEY, { value: val.to_s, http_only: true, same_site: :lax })
        end

        # @return [PgEventstore::Connection]
        def connection
          PgEventstore.connection(current_config)
        end

        # @param collection [PgEventstore::Web::Paginator::BaseCollection]
        # @return [void]
        def paginated_json_response(collection)
          halt 200, {
            results: collection.collection,
            pagination: { more: !collection.next_page_starting_id.nil?, starting_id: collection.next_page_starting_id }
          }.to_json
        end

        # @param fallback_url [String]
        # @return [String]
        def redirect_back_url(fallback_url:)
          return fallback_url if request.referer.to_s.empty?

          "#{request.referer}#{params[:hash]}"
        end

        # Shortcut to escape html
        # @param text [String]
        # @return [String]
        def h(text)
          Rack::Utils.escape_html(text)
        end

        # @param path [String]
        # @return [String]
        def asset_url(path)
          url("#{path}?v=#{PgEventstore::VERSION}")
        end

        # @return [Boolean]
        def resolve_link_tos?
          params.key?(:resolve_link_tos) ? params[:resolve_link_tos] == 'true' : true
        end

        # @param val [Hash]
        def flash_message=(val)
          val = Base64.urlsafe_encode64(val.to_json)
          response.set_cookie(
            COOKIES_FLASH_MESSAGE_KEY, { value: val, http_only: false, same_site: :lax, path: '/' }
          )
        end
      end

      get '/' do
        @collection = Paginator::EventsCollection.new(
          current_config,
          starting_id: params[:starting_id]&.to_i,
          per_page: Paginator::EventsCollection::PER_PAGE[params[:per_page]],
          order: Paginator::EventsCollection::SQL_DIRECTIONS[params[:order]],
          options: {
            filter: { event_types: events_filter, streams: streams_filter },
            resolve_link_tos: resolve_link_tos?
          },
          system_stream: system_stream
        )

        if request.xhr?
          content_type 'application/json'
          halt 200, {
            events: erb(:'home/partials/events', { layout: false }, { events: @collection.collection }),
            total_count: total_count(@collection.total_count),
            pagination: erb(:'home/partials/pagination_links', { layout: false }, { collection: @collection })
          }.to_json
        else
          erb :'home/dashboard'
        end
      end

      get '/subscriptions' do
        @set_collection = Subscriptions::SetCollection.new(connection)
        @current_set = params[:set_name] || @set_collection.names.first
        @association = Subscriptions::SubscriptionsToSetAssociation.new(
          subscriptions_set: Subscriptions::SubscriptionsSet.new(connection, @current_set).subscriptions_set,
          subscriptions: Subscriptions::Subscriptions.new(connection, @current_set).subscriptions
        )
        erb :'subscriptions/index'
      end

      get '/subscriptions/:state' do
        @set_collection = Subscriptions::WithState::SetCollection.new(connection, state: params[:state])
        @current_set = params[:set_name] || @set_collection.names.first
        subscriptions_set = Subscriptions::WithState::SubscriptionsSet.new(
          connection, @current_set, state: params[:state]
        ).subscriptions_set
        subscriptions = Subscriptions::WithState::Subscriptions.new(
          connection, @current_set, state: params[:state]
        ).subscriptions
        @association = Subscriptions::SubscriptionsToSetAssociation.new(
          subscriptions_set: subscriptions_set,
          subscriptions: subscriptions
        )
        erb :'subscriptions/index'
      end

      post '/change_config' do
        self.current_config = resolve_config_by_name(params[:config]&.to_s&.to_sym)
        redirect(redirect_back_url(fallback_url: '/'))
      end

      get '/stream_contexts_filtering', provides: :json do
        collection = Paginator::StreamContextsCollection.new(
          current_config,
          starting_id: params[:starting_id],
          per_page: Paginator::StreamContextsCollection::PER_PAGE,
          order: :asc,
          options: { query: params[:term] }
        )
        paginated_json_response(collection)
      end

      get '/stream_names_filtering', provides: :json do
        collection = Paginator::StreamNamesCollection.new(
          current_config,
          starting_id: params[:starting_id],
          per_page: Paginator::StreamNamesCollection::PER_PAGE,
          order: :asc,
          options: { query: params[:term], context: params[:context] }
        )
        paginated_json_response(collection)
      end

      get '/stream_ids_filtering', provides: :json do
        collection = Paginator::StreamIdsCollection.new(
          current_config,
          starting_id: params[:starting_id],
          per_page: Paginator::StreamIdsCollection::PER_PAGE,
          order: :asc,
          options: { query: params[:term], context: params[:context], stream_name: params[:stream_name] }
        )
        paginated_json_response(collection)
      end

      get '/event_types_filtering', provides: :json do
        collection = Paginator::EventTypesCollection.new(
          current_config,
          starting_id: params[:starting_id],
          per_page: Paginator::EventTypesCollection::PER_PAGE,
          order: :asc,
          options: { query: params[:term] }
        )
        paginated_json_response(collection)
      end

      post '/subscription_cmd/:set_id/:id/:cmd' do
        validate_subscription_cmd(params[:cmd])
        cmd_class = SubscriptionRunnerCommands.command_class(params[:cmd])
        SubscriptionCommandQueries.new(connection).find_or_create_by(
          subscriptions_set_id: Integer(params[:set_id]),
          subscription_id: Integer(params[:id]),
          command_name: cmd_class.new.name,
          data: cmd_class.parse_data(Hash(params[:data]))
        )

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/subscriptions_set_cmd/:id/:cmd' do
        validate_subscriptions_set_cmd(params[:cmd])
        cmd_class = SubscriptionFeederCommands.command_class(params[:cmd])
        SubscriptionsSetCommandQueries.new(connection).find_or_create_by(
          subscriptions_set_id: Integer(params[:id]),
          command_name: cmd_class.new.name,
          data: cmd_class.parse_data(Hash(params[:data]))
        )

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/delete_subscriptions_set/:id' do
        SubscriptionsSetQueries.new(connection).delete(Integer(params[:id]))

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/delete_subscription/:id' do
        SubscriptionQueries.new(connection).delete(Integer(params[:id]))

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/delete_all_subscriptions' do
        params[:ids].each do |id|
          SubscriptionQueries.new(connection).delete(Integer(id))
        end

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/delete_event/:global_position' do
        params in { data: { force: String => force } }
        global_position = params[:global_position].to_i
        force = force == 'true'
        event = PgEventstore.client(current_config).read(
          PgEventstore::Stream.all_stream, options: { max_count: 1, from_position: global_position }
        ).first
        if event&.global_position == global_position
          begin
            PgEventstore.maintenance(current_config).delete_event(event, force: force)
            self.flash_message = {
              message: "An event at global position #{event.global_position} has been deleted successfully.",
              kind: 'success'
            }
          rescue TooManyRecordsToLockError => e
            text = <<~TEXT
              Could not delete an event at global position #{event.global_position} - too many \
              records(~#{e.number_of_records}) to lock.
            TEXT
            self.flash_message = { message: text, kind: 'error' }
          end
        else
          self.flash_message = { message: 'Failed to delete an event - event does not exist.', kind: 'warning' }
        end
        redirect(redirect_back_url(fallback_url: '/'))
      end

      post '/delete_stream/:context/:stream_name/:stream_id' do
        attrs = Hash[params.slice(:context, :stream_name, :stream_id)].transform_keys(&:to_sym)
        stream = PgEventstore::Stream.new(**attrs)
        PgEventstore.maintenance(current_config).delete_stream(stream)
        self.flash_message = {
          message: "Stream #{stream.to_hash} has been successfully deleted.",
          kind: 'success'
        }
        redirect(redirect_back_url(fallback_url: '/'))
      end
    end
  end
end
