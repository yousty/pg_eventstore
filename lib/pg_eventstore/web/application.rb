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

      helpers(Paginator::Helpers) do
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

        # @param collection [PgEventstore::Paginator::BaseCollection]
        # @return [void]
        def paginated_json_response(collection)
          halt 200, {
            results: collection.collection,
            pagination: { more: !collection.next_page_starting_id.nil?, starting_id: collection.next_page_starting_id }
          }.to_json
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
        erb :'home/dashboard'
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
    end
  end
end
