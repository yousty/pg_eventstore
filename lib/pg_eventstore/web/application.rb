# frozen_string_literal: true

require 'securerandom'

module PgEventstore
  module Web
    class Application < Sinatra::Base
      set :static_cache_control, [:private, max_age: 86400]
      set :environment, -> { (ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV['APP_ENV'])&.to_sym || :development }
      set :logging, -> { environment == :development || environment == :test }
      set :erb, layout: :'layouts/application'
      set :sessions, true
      set :session_secret, ENV.fetch('SECRET_KEY_BASE') { SecureRandom.hex(64) }

      helpers(Paginator::Helpers, Subscriptions::Helpers) do
        # @return [Array<Hash>, nil]
        def streams_filter
          params in { filter: { streams: Array => streams } }
          streams&.select { _1 in { context: String, stream_name: String, stream_id: String } }&.map do
            Hash[_1.reject { |_, value| value == '' }].transform_keys(&:to_sym)
          end&.reject { _1.empty? }
        end

        # @return [Array<String>, nil]
        def events_filter
          params in { filter: { events: Array => events } }
          events&.select { _1.is_a?(String) && _1 != '' }
        end

        # @return [Symbol]
        def current_config
          PgEventstore.available_configs.include?(session[:current_config]) ? session[:current_config] : :default
        end

        # @return [PgEventstore::Connection]
        def connection
          PgEventstore.connection(current_config)
        end

        # @param collection [PgEventstore::Paginator::BaseCollection]
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
      end

      get '/' do
        @collection = Paginator::EventsCollection.new(
          current_config,
          starting_id: params[:starting_id]&.to_i,
          per_page: Paginator::EventsCollection::PER_PAGE[params[:per_page]],
          order: Paginator::EventsCollection::SQL_DIRECTIONS[params[:order]],
          options: { filter: { event_types: events_filter, streams: streams_filter } }
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

      post '/change_config' do
        config = params[:config]&.to_sym
        config = :default unless PgEventstore.available_configs.include?(config)
        session[:current_config] = config
        redirect(url('/'))
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
        puts SubscriptionCommandQueries.new(connection).find_or_create_by(
          subscriptions_set_id: params[:set_id],
          subscription_id: params[:id],
          command_name: CommandHandlers::SubscriptionRunnersCommands::AVAILABLE_COMMANDS.fetch(params[:cmd].to_sym)
        )

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/subscriptions_set_cmd/:id/:cmd' do
        SubscriptionsSetCommandQueries.new(connection).find_or_create_by(
          subscriptions_set_id: params[:id],
          command_name: CommandHandlers::SubscriptionFeederCommands::AVAILABLE_COMMANDS.fetch(params[:cmd].to_sym)
        )

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/delete_subscriptions_set/:id' do
        SubscriptionsSetQueries.new(connection).delete(params[:id])

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/delete_subscription/:id' do
        SubscriptionQueries.new(connection).delete(params[:id])

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end

      post '/delete_all_subscriptions' do
        params[:ids].each do |id|
          SubscriptionQueries.new(connection).delete(id)
        end

        redirect redirect_back_url(fallback_url: url('/subscriptions'))
      end
    end
  end
end
