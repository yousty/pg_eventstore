# frozen_string_literal: true

module PgEventstore
  module Commands
    module RevisionCheck
      # @!visibility private
      class ExpectedRevision
        class StreamRevision < Struct.new(:revision)
          # @!attribute revision
          #   @return [Symbol, Integer]
        end

        class EventTypeRevisions < Struct.new(:revisions)
          # @!attribute revisions
          #   @return [Hash<String, Symbol>, Hash<String, Integer>]
        end

        class << self
          # @param expected_revision [Symbol, Integer, Hash<String, Symbol>, Hash<String, Integer>, nil]
          # @return [ExpectedRevision::StreamRevision, ExpectedRevision::EventTypeRevisions, nil]
          def build(expected_revision)
            case expected_revision
            in Integer | Symbol
              StreamRevision.new(revision: expected_revision)
            in Hash
              revisions = expected_revision.select { |k, v| k.is_a?(String) && v in Integer | Symbol }
              EventTypeRevisions.new(revisions:)
            in NilClass
              # do nothing
            else
              raise ArgumentError, "Unsupported expected revision #{expected_revision.inspect}."
            end
          end
        end
      end
    end
  end
end
