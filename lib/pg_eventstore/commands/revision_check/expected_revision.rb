# frozen_string_literal: true

module PgEventstore
  module Commands
    module RevisionCheck
      # @!visibility private
      class ExpectedRevision
        class StreamRevision
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute revision
          #   @return [Symbol, Integer]
          attribute(:revision)
        end

        class EventTypeRevision
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute expected_revision
          #   @return [Symbol, Integer]
          attribute(:expected_revision)
          # @!attribute event_type
          #   @return [String, nil]
          attribute(:event_type)
          # @!attribute sequence_number
          #   @return [Integer]
          attribute(:sequence_number)
        end

        class EventTypeRevisionWithMarkers
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute expected_revision
          #   @return [Symbol, Integer]
          attribute(:expected_revision)
          # @!attribute event_type
          #   @return [String, nil]
          attribute(:event_type)
          # @!attribute markers
          #   @return [Array<String>]
          attribute(:markers)
          # @!attribute sequence_number
          #   @return [Integer]
          attribute(:sequence_number)
        end

        class MarkersRevision
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute expected_revision
          #   @return [Symbol, Integer]
          attribute(:expected_revision)
          # @!attribute markers
          #   @return [Array<String>]
          attribute(:markers)
          # @!attribute sequence_number
          #   @return [Integer]
          attribute(:sequence_number)
        end

        class EventTypeRevisions
          include Extensions::OptionsExtension
          include Extensions::OptionsDefaults

          # @!attribute revisions
          #   @return [Array<EventTypeRevision, EventTypeRevisionWithMarkers, MarkersRevision>]
          attribute(:revisions)
        end

        class << self
          # @param expected_revision [Symbol, Integer, Hash]
          # @return [ExpectedRevision::StreamRevision, ExpectedRevision::EventTypeRevisions, nil]
          def build(expected_revision)
            case expected_revision
            in Integer | Symbol
              StreamRevision.new(revision: expected_revision)
            in Hash
              revisions = expected_revision.map.with_index do |(key, value), index|
                case [key, value]
                # { 'Foo' => 1 }, { 'Foo' => :any }, etc
                in [String, Integer | Symbol]
                  EventTypeRevision.new(event_type: key, expected_revision: value, sequence_number: index)
                  # { 'Foo' => { expected_revision: 1, markers: ['foo'] } },
                  # { 'Foo' => { expected_revision: :any, markers: ['foo'] } }, etc
                in [String, Hash]
                  markers = extract_markers(value)
                  expected_revision = extract_expected_revision(value)
                  EventTypeRevisionWithMarkers.new(
                    event_type: key, expected_revision:, markers:, sequence_number: index
                  )
                # { any: => { expected_revision: 1, markers: ['foo'] } },
                # { any: => { expected_revision: :any, markers: ['foo'] } }, etc
                in [:any, Hash]
                  markers = extract_markers(value)
                  expected_revision = extract_expected_revision(value)
                  MarkersRevision.new(expected_revision:, markers:, sequence_number: index)
                else
                  nil
                end
              end.compact
              EventTypeRevisions.new(revisions:)
            in NilClass
              # do nothing
            else
              raise ArgumentError, "Unsupported :expected_revision #{expected_revision.inspect} option."
            end
          end

          private

          # @param hash [Hash]
          # @return [Symbol, Integer]
          def extract_expected_revision(hash)
            hash in { expected_revision: Symbol | Integer => expected_revision }
            expected_revision ||
              raise(ArgumentError, "Unsupported expected revision #{hash[:expected_revision].inspect} value.")
          end

          # @param hash [Hash]
          # @return [Array<String>]
          def extract_markers(hash)
            markers = hash[:markers]&.grep(String)
            raise ArgumentError, "Unsupported markers: #{hash[:markers].inspect}." if markers.nil? || markers.empty?

            markers
          end
        end
      end
    end
  end
end
