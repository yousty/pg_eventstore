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
