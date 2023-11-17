# frozen_string_literal: true

module PgEventstore
  class Event
    include Extensions::OptionsExtension

    UUID_REGEXP = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\z/i.freeze

    attr_reader :id, :type, :global_position, :context, :stream_name, :stream_id, :stream_revision, :data, :metadata,
                :link_id, :created_at

    def initialize(**attributes)
      structured_attributes(attributes).each do |attr, value|
        instance_variable_set(:"@#{attr}", value)
      end
    end

    # @return [PgEventstore::Stream]
    def stream
      Stream.new(context: context, stream_name: stream_name, stream_id: stream_id)
    end

    private

    # @param options [Hash]
    # @return [Hash]
    def structured_attributes(options)
      options in { id: UUID_REGEXP => id }
      options in { type: String => type }
      options in { global_position: String => global_position }
      options in { context: String => context }
      options in { stream_name: String => stream_name }
      options in { stream_id: String => stream_id }
      options in { stream_revision: Integer => stream_revision }
      options in { data: Hash => data }
      options in { metadata: Hash => metadata }
      options in { link_id: Integer => link_id }
      options in { created_at: Time => created_at }

      attrs = %i[id type global_position context stream_name stream_id stream_revision data metadata link_id created_at]
      attrs.each_with_object({}) do |var, res|
        res[var] = binding.local_variable_get(var)
      end
    end
  end
end
