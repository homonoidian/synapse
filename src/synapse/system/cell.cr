class Cell
  class Memory
    include LuaCallable

    def initialize(@cell : Cell)
      @store = {} of String => Memorable
    end

    def _index(key : String)
      @store[key]?
    end

    def _newindex(key : String, val : Memorable)
      @store[key] = val
      @cell.on_memory_changed
    end
  end

  # Returns the unique identifier of this cell.
  getter id : UUID

  # Returns the memory of this cell.
  getter memory : Memory

  def initialize(
    @id = UUID.random,
    @protocols = ProtocolCollection.new,
    @relatives = Set(Cell).new
  )
    @avatars = Set(CellAvatar).new

    @memory = uninitialized Memory
    @memory = Memory.new(self)

    @relatives << self
  end

  # Makes this cell adhere to the given *protocol*.
  def adhere(protocol : Protocol)
    @protocols.summon(protocol)
  end

  # Replaces the protocols used by this cell with the given *protocols*.
  def adhere(protocols : ProtocolCollection)
    @protocols = protocols
  end

  # Yields avatars of this cell.
  def each_avatar(&)
    @avatars.each do |avatar|
      yield avatar
    end
  end

  # Yields relatives of this cell, *including this cell itself*.
  def each_relative(&)
    @relatives.each do |relative|
      yield relative
    end
  end

  # Yields avatars of the relatives of this cell, *including avatars of
  # this cell itself*.
  def each_relative_avatar(&)
    each_relative do |relative|
      relative.each_avatar do |avatar|
        yield avatar
      end
    end
  end

  # Yields each protocol owned by this cell wrapped in `OwnedProtocol`,
  # followed by its name.
  def each_owned_protocol_with_name(&)
    @protocols.each_named_protocol do |protocol, name|
      yield OwnedProtocol.new(name, protocol), name
    end
  end

  # Invoked when an *avatar* of this cell is born.
  def born(avatar : CellAvatar)
    @avatars << avatar
    @protocols.born(avatar)
  end

  # Invoked when an *avatar* of this cell dies.
  def died(avatar : CellAvatar)
    @avatars.delete(avatar)

    return unless @avatars.empty?

    # Remove the last reference to self (presumably), which will make
    # the GC collect this cell later.
    @relatives.delete(self)
  end

  # Invoked when the content of this cell's memory changes.
  def on_memory_changed
    each_avatar do |avatar|
      @protocols.on_memory_changed(avatar)
    end
  end

  # Invoked when an *avatar* of this cell receives the given *vesicle*.
  def receive(avatar : CellAvatar, vesicle : Vesicle)
    @protocols.express(receiver: avatar, vesicle: vesicle)
  end

  # Invoked when *avatar* undergoes systole (see `Protocol#systole`).
  def systole(avatar : CellAvatar)
    @protocols.systole(receiver: avatar)
  end

  # Invoked when *avatar* undergoes dyastole (see `Protocol#dyastole`).
  def dyastole(avatar : CellAvatar)
    @protocols.dyastole(avatar)
  end

  # Builds and returns a copy of this cell.
  def copy
    Cell.new(UUID.random, @protocols, @relatives)
  end

  # Returns a new `CellEditor` for this cell.
  def to_editor
    editor = CellEditor.new
    editor.append(@protocols)
    editor
  end

  def_equals_and_hash @id
end
