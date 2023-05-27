module IVesicleDecayHandler # FIXME: ???
  # Called when *vesicle* decays in the *protoplasm* this object is
  # listening to.
  abstract def decayed(protoplasm : Protoplasm, vesicle : Vesicle)
end

module INotificationHandler # FIXME: ???
  abstract def notify(keyword : Symbol)
end

struct Cell
  include IVesicleDecayHandler
  include INotificationHandler

  class Memory
    include LuaCallable

    def initialize
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
  @id = App.genid

  # A set of avatars of this cell.
  #
  # Note that avatars are not copies; they are "instances" of
  # this cell in different tanks.
  @avatars = Set(CellAvatar).new

  def initialize
    protoplasm = Protoplasm.new

    @graph = AgentGraph.new(protoplasm)
    @memory = Memory.new

    @relatives = Set(Cell).new
    @relatives << self

    protoplasm.add_vesicle_decay_handler(self)
    protoplasm.add_notification_handler(self)
  end

  protected def initialize(@graph, @relatives)
    @memory = Memory.new
    @relatives << self
  end

  def decayed(protoplasm : Protoplasm, vesicle : Vesicle)
    # The more vesicles there are in the protoplasm, the more the
    # chance of destruction of this vesicle.
    chance = 0.5*Math::E**(0.05/protoplasm.growth) - 0.5
    if chance < 0.03 # < 3%
      chance = 0.01  # = 1%
    end

    return unless rand < chance

    each_avatar &.receive(vesicle)
  end

  def notify(keyword : Symbol)
    case keyword
    when :birth_rule_changed
      each_avatar { |avatar| born(avatar) }
    end
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

  # Looks up and returns a protocol with the given *name*, owned
  # by this cell and wrapped in `OwnedProtocol`. If not found,
  # returns nil.
  def owned_protocol?(name : String)
    @graph.each_protocol_agent do |protocol|
      next unless other = protocol.name?
      next unless other == name
      return OwnedProtocol.new(name, protocol)
    end
  end

  # Yields owned protocols *agent* has an edge with.
  def each_owned_protocol_edge(of agent : RuleAgent)
    @graph.each_protocol_agent(of: agent) do |edge|
      yield OwnedProtocol.new(edge.name?, edge)
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

  # Returns whether this cell adheres to a protocol with the given *name*.
  # Obviously enough, only owned protocols with name are checked.
  def adheres?(name : String)
    each_owned_protocol_with_name do |_, other|
      return true if name == other
    end

    false
  end

  def selective_fill(recipient : AgentGraph, &)
    @graph.fill(recipient) do |protocol|
      yield protocol
    end
  end

  # Called when an *avatar* of this cell is born.
  def born(avatar : CellAvatar)
    @avatars << avatar

    @graph.each_enabled_birth_agent do |agent|
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
    @graph.each_enabled_keyword_agent_matching(vesicle) do |agent|
      agent.express(receiver: avatar, vesicle: vesicle)
    end
  end

  @_rules = Set(HeartbeatRuleAgent).new

  # Called on every tick of *avatar*. Gives opportunity of expression to
  # heartbeat rules of *avatar*.
  def tick(delta : Float, avatar : CellAvatar)
    @graph.each_protocol_agent do |protocol|
      @_rules.clear
      @graph.each_rule_agent(of: protocol, a: HeartbeatRuleAgent) do |rule|
        @_rules << rule
      end
      protocol.heartbeat(agents_readonly: @_rules, receiver: avatar)
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
