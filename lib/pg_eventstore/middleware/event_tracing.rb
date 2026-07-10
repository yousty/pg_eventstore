# frozen_string_literal: true

module PgEventstore
  module Middleware
    class EventTracing
      include Middleware

      # @return [String]
      CAUSATION_ID_KEY = "#{Event::SYSTEM_SYMBOL}CaId".freeze
      # @return [String]
      CORRELATION_ID_KEY = "#{Event::SYSTEM_SYMBOL}CoId".freeze

      class << self
        # @param marker [String]
        # @return [PgEventstore::FeatureMarker]
        def causation_marker(marker)
          FeatureMarker.new(marker:, purpose: :causation_id, description: 'Causation ID')
        end

        # @param marker [String]
        # @return [PgEventstore::FeatureMarker]
        def correlation_marker(marker)
          FeatureMarker.new(marker:, purpose: :correlation_id, description: 'Correlation ID')
        end
      end

      def serialize(event)
        if event.caused_by
          event.causation_id = event.caused_by.id.dup
          event.metadata[CAUSATION_ID_KEY] = event.causation_id
          event.feature_markers.push(self.class.causation_marker(event.causation_id))
        end

        event.correlation_id = event.caused_by&.correlation_id&.dup || SecureRandom.uuid_v7
        event.metadata[CORRELATION_ID_KEY] = event.correlation_id
        event.feature_markers.push(self.class.correlation_marker(event.correlation_id))
      end

      # rubocop:disable Style/GuardClause
      def deserialize(event)
        if event.metadata[CAUSATION_ID_KEY]
          event.causation_id = event.metadata[CAUSATION_ID_KEY]
          event.feature_markers.push(self.class.causation_marker(event.causation_id))
        end
        if event.metadata[CORRELATION_ID_KEY]
          event.correlation_id = event.metadata[CORRELATION_ID_KEY]
          event.feature_markers.push(self.class.correlation_marker(event.correlation_id))
        end
      end
      # rubocop:enable Style/GuardClause
    end
  end
end
