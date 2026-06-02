# frozen_string_literal: true

class InstantChunk
  include PgEventstore::Chunks::Chunk

  # @param entities [Array]
  def initialize(entities)
    @entities = entities
  end

  def take(size)
    @entities.slice!(0...size)
  end

  def drained?
    @entities.empty?
  end

  def size
    @entities.size
  end

  def last
    @entities.last
  end
end

class EventIndexesChunk
  include PgEventstore::Chunks::Chunk

  class << self
    def create_indexes(entities, make_links: false, links_starting_id: 0)
      indexes = entities.map { PgEventstore::EventGlobalIndex.new(_1) }
      new(indexes, make_links, links_starting_id)
    end
  end

  # @param entities [Array]
  def initialize(entities, make_links, links_starting_id)
    @entities = entities
    @make_links = make_links
    @links_starting_id = links_starting_id
  end

  def take(size)
    id_seq = '00000000-0000-0000-0000-000000000000'
    link_id_seq = @links_starting_id - 1
    @entities.slice!(0...size).map do |event_idx|
      id_seq = id_seq.next
      link_id_seq = link_id_seq.next
      { 'global_position' => event_idx.global_position, 'id' => id_seq }.tap do |raw_event|
        raw_event['link'] = { 'global_position' => link_id_seq } if @make_links
      end
    end
  end

  def drained?
    @entities.empty?
  end

  def size
    @entities.size
  end

  def last
    @entities.last
  end
end

class LazyChunk
  include PgEventstore::Chunks::Chunk

  # @param entities [Array]
  def initialize(entities)
    @entities = entities
  end

  def take(_size)
    [@entities.shift]
  end

  def drained?
    @entities.empty?
  end

  def size
    @entities.size
  end

  def last
    @entities.last
  end
end
