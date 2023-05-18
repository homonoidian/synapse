struct Cell
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
    end
  end

  # Returns the memory of this cell.
  getter memory : Memory

  # Unique identifier of this cell, used in hashing and comparison.
  @id = UUID.random

  # A set of avatars of this cell.
  #
  # Note that avatars are not copies; they are "instances" of
  # this cell in different tanks.
  @avatars = Set(CellAvatar).new

  def initialize
    @graph = AgentGraph.new(Protoplasm.new)
    @relatives = Set(Cell).new

    @memory = uninitialized Memory
    @memory = Memory.new(self)

    @relatives << self
  end

  protected def initialize(@graph, @relatives)
    @memory = uninitialized Memory
    @memory = Memory.new(self)

    @relatives << self
  end

  def browse(hub : AgentBrowserHub, size : Vector2) : AgentBrowser
    @graph.browse(hub, size)
  end

  def pack(protocol : ProtocolAgent)
    ruleset = {} of Rule => BufferEditorColumnInstant

    @graph.each_rule_agent(of: protocol) do |agent|
      agent.pack(into: ruleset)
    end

    PackedProtocol.new(protocol.name?.not_nil!, protocol.enabled?, ruleset)
  end

  def adhere(hub : AgentBrowserHub, name : String, enabled : Bool, ruleset : Hash(Rule, BufferEditorColumnInstant), &)
    protocol = nil

    @graph.each_protocol_agent(named: name) do |existing|
      protocol = existing
      break
    end

    protocol ||= begin
      it = @graph.naturalize(ProtocolAgent)
      it.mid = hub.size / 2
      it.rename(name)
      yield it
      it.summon
      unless enabled
        it.disable
      end
      it
    end

    ruleset.each do |rule, instant|
      @graph.import(protocol, rule, instant) do |agent|
        yield agent
      end
    end
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
    @graph.each_protocol_agent do |protocol|
      next unless name = protocol.name?

      yield OwnedProtocol.new(name, protocol), name
    end
  end

  def selective_fill(recipient : AgentGraph, &)
    @graph.fill(recipient) do |protocol|
      yield protocol
    end
  end

  def unfail
    @graph.each_agent &.unfail
  end

  # Called when an *avatar* of this cell is born.
  def born(avatar : CellAvatar)
    @avatars << avatar

    @graph.each_running_birth_agent do |agent|
      agent.express(receiver: avatar)
    end
  end

  # Called when an *avatar* of this cell dies.
  def died(avatar : CellAvatar)
    @avatars.delete(avatar)

    return unless @avatars.empty?

    @relatives.delete(self)
  end

  # Called when an *avatar* of this cell receives the given *vesicle*.
  def receive(avatar : CellAvatar, vesicle : Vesicle)
    @graph.each_running_keyword_agent_matching(vesicle) do |agent|
      agent.express(receiver: avatar, vesicle: vesicle)
    end
  end

  # Called on every tick of *avatar*. Controls expression of heartbeat
  # rules for *avatar*.
  def tick(delta : Float, avatar : CellAvatar)
    @graph.each_running_heartbeat_agent do |agent|
      agent.express(receiver: avatar)
    end
  end

  # Builds and returns a copy of this cell, possibly one within a
  # different *graph*.
  #
  # This method does not talk to *graph*, but *graph* may wish to
  # participates in acquisition. Do not use this method if you are
  # unsure; perhaps look at `AgentGraph#naturalize`.
  def copy(graph : AgentGraph = @graph)
    Cell.new(graph, @relatives)
  end

  # When created, each cell is assigned a globally unique identifier.
  # Hashing and comparison of cells is done using this identifier.
  def_equals_and_hash @id
end
