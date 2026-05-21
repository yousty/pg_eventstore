# frozen_string_literal: true

module PgEventstore
  module Commands
    module RevisionCheck
      class ExpectedRevision
        StreamRevision = Struct.new(:revision)
        EventTypeRevisions = Struct.new(:revisions)

        class << self
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
              raise ArgumentError
            end
          end
        end
      end
    end
  end
end
