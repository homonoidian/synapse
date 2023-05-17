# `AgentGraph` is an unordered graph that keeps track of how different
# `Agent`s relate to each other in a `Protoplasm`.
#
# It also facilitates exploration of the most kind of agent relationship,
# namely the protocol-rule agent relationship.
struct AgentGraph
  def initialize(@protoplasm : Protoplasm)
    # Maps protocol agents to rule agents for e.g. rule lookup.
    @graph = {} of ProtocolAgent => Set(RuleAgent)

    # Maps protocol agents to *all* constraints they've created so
    # that they can be cleaned up when the protocol is removed.
    @links = {} of ProtocolAgent => Set(AgentAgentConstraint)

    # A set of *all* edges in the graph *including* those in @links.
    @edges = Set(AgentEdge).new
  end

  # Builds and returns an `AgentBrowser` object for this graph.
  #
  # *size* is the size of the new browser, in pixels.
  def browse(hub : AgentBrowserHub, size : Vector2) : AgentBrowser
    AgentBrowser.new(hub, size, @protoplasm, self)
  end

  # Yields *all* edges in this graph in no particular order. *All*
  # means including both `AgentAgentEdge`s and `AgentPointEdge`s.
  def each_edge(&)
    @edges.each do |edge|
      yield edge
    end
  end

  # Yields *all* agents from this graph in no particular order. Agents
  # that are not part of the graph (those which are disconnected)
  # are not yielded.
  def each_agent(&)
    @graph.each do |protocol, rules|
      yield protocol

      rules.each do |rule|
        yield rule
      end
    end
  end

  # Yields protocol agents *with rules* from this graph in no
  # particular order.
  def each_protocol_agent(&)
    @graph.each_key do |protocol|
      yield protocol
    end
  end

  # Yields *all* protocol agents the given *rule* agent is connected
  # to in no particular order.
  def each_protocol_agent(*, of rule : RuleAgent, &)
    @graph.each do |protocol, rules|
      rules.each do |other|
        next unless rule.same?(other)
        yield protocol
      end
    end
  end

  # Yields *all* protocol agents with the given *name*.
  #
  # Protocol agents are identified by their own globally unique ID,
  # and not by name. Therefore, having multiple protocol agents with
  # the same name is allowed.
  def each_protocol_agent(*, named name : String, &)
    each_protocol_agent do |protocol|
      next unless protocol.name? == name
      yield protocol
    end
  end

  # Yields rule agents of the given *protocol* in no particular order.
  # Does nothing if *protocol* is not a vertex of this graph.
  def each_rule_agent(*, of protocol : ProtocolAgent, &)
    return unless rules = @graph[protocol]?

    rules.each do |rule|
      yield rule
    end
  end

  # Yields rule agents of the given *protocol* that match the *other* rule.
  def each_rule_agent(*, of protocol : ProtocolAgent, matching other : Rule, &)
    each_rule_agent(of: protocol) do |rule|
      next unless rule.matches?(other)
      yield rule
    end
  end

  # Yields all *running* (not paused) rule agents from this graph in
  # no particular order.
  #
  # For a rule agent to be considered running, it must not be paused
  # itself, and one of the protocol agents it is connected to must
  # not be paused (i.e. the rule agent must be reachable via a protocol
  # agent that is itself running).
  def each_running_rule_agent(&)
    @graph.each do |protocol, rules|
      next unless protocol.enabled?

      rules.each do |rule|
        next unless rule.enabled?
        yield rule
      end
    end
  end

  # Yields all *running* rule agents of the given *type*, in no
  # particular order.
  #
  # See `each_running_rule_agent`.
  def each_running_rule_agent(*, a type : T.class, &) forall T
    each_running_rule_agent do |rule|
      next unless rule.is_a?(T)
      yield rule
    end
  end

  # Yields running birth rule agents from this graph, in no
  # particular order.
  def each_running_birth_agent(&)
    each_running_rule_agent(a: BirthRuleAgent) do |rule|
      yield rule
    end
  end

  # Yields only those running rule agents whose rules are
  # expressible from *vesicle* and match *vesicle*, in no
  # particular order.
  def each_running_rule_agent_matching(vesicle : Vesicle, &)
    each_running_rule_agent(a: RuleExpressibleFromVesicle) do |rule|
      next unless rule.matches?(vesicle)
      yield rule
    end
  end

  # Yields running heartbeat rule agents from this graph, in
  # no particular order.
  def each_running_heartbeat_agent(&)
    each_running_rule_agent(a: HeartbeatRuleAgent) do |rule|
      yield rule
    end
  end

  # Yields protocol agents from this graph, and fills the *recipient*
  # graph only with those protocol agents (and rule agents connected
  # to them) for which the block returned a truthy value.
  def fill(recipient : AgentGraph, &)
    each_protocol_agent do |protocol|
      next unless yield protocol

      parent = recipient.naturalize(protocol)

      each_rule_agent(of: protocol) do |rule|
        child = recipient.naturalize(rule)

        recipient.connect(parent, child)
      end
    end
  end

  # Returns a copy of *agent* that is "naturalized" in this graph,
  # i.e., one that lives in the protoplasm associated with this
  # graph rather than in *agent*'s original protoplasm.
  def naturalize(agent : Agent)
    agent.copy(@protoplasm)
  end

  # Returns an instance of agent class *cls* "naturalized" in this
  # graph, i.e., one that lives in the protoplasm associated with
  # this graph.
  def naturalize(cls : Agent.class)
    cls.new(@protoplasm)
  end

  # Updates (creating, if necessary) an agent matching the given
  # *rule* and connected to *protocol* agent.
  #
  # If *rule* is implemented by an existing agent connected
  # to *protocol* agent, simply updates the existing agent
  # from *instant*.
  #
  # If *rule* is not implemented by any agent, creates and
  # yields an agent appropriately initiailized just before
  # summoning it. Consecutively connects the created agent
  # to *protocol*.
  def import(protocol : ProtocolAgent, rule : Rule, instant, &)
    each_rule_agent(of: protocol, matching: rule) do |existing|
      existing.drain(instant)
      return
    end

    agent = rule.to_agent(@protoplasm, instant)
    agent.mid = protocol.mid
    yield agent

    agent.summon

    connect(protocol, agent)
  end

  # Inserts the given *edge* into this graph.
  #
  # You probably don't need to use this method. Rather, let *edge*
  # insert itself using `AgentEdge#summon`.
  def insert(edge : AgentEdge)
    @edges << edge

    edge.constrain(@protoplasm)
  end

  # Removes the given *edge* from this graph.
  #
  # You probably don't need to use this method. Rather, let *edge*
  # remove itself using `AgentEdge#dismiss`.
  def remove(edge : AgentEdge)
    @edges.delete(edge)

    # We also store edges in @links so don't forget to delete
    # it there too.
    @links.each_value &.delete(edge)

    edge.loosen(@protoplasm)
  end

  # Connects the given agents *a* and *b* with a springy link
  # which will keep them close to each other. Note that the
  # link is invisible.
  def keep_close(a : Agent, b : Agent)
    KeepcloseLink.new(self, a, b).tap &.summon
  end

  # Connects the given agents *a* and *b* with a keepaway link.
  # The link will keep them some distance away, but also won't
  # let them get too far from each other. Returns the resulting
  # link object.
  #
  # You don't need to summon the link, it's going to be summoned
  # already and be in the tank. Note that the link is invisible.
  def keep_away(a : Agent, b : Agent)
    KeepawayLink.new(self, a, b).tap &.summon
  end

  # Connects the given agents *a* and *b* with a visible agent-
  # agent edge.
  #
  # You don't need to summon the edge, it's going to be summoned
  # already and be in the tank.
  def edge(a : Agent, b : Agent)
    AgentAgentEdge.new(self, a, b).tap &.summon
  end

  # Returns whether this graph (*being an unordered graph*)
  # contains an edge with the given agents *a*, *b*.
  def connected?(a : Agent, b : Agent)
    @edges.any? { |edge| edge.is_a?(AgentAgentEdge) && edge.all?(a, b) }
  end

  # Creates an `AgentPointEdge`: an edge between the given *agent*
  # and a *point* location. Returns the resulting edge object.
  #
  # You don't need to summon it, it's going to be summoned already
  # and be in the tank.
  def connect(agent : Agent, point : Vector2)
    AgentPointEdge.new(self, agent, point).tap &.summon
  end

  # Connects *protocol* to the given *rule* agent.
  #
  # Does a lot of things to make the resulting graph look nice, but
  # overall, you can think of this method as simply creating an
  # `AgentAgentEdge` between *protocol* and *rule*.
  def connect(protocol : ProtocolAgent, rule : RuleAgent)
    unless rules = @graph[protocol]?
      @links[protocol] = Set(AgentAgentConstraint).new
      @graph.each_key { |other| @links[protocol] << keep_away(protocol, other) }
      @graph[protocol] = Set{rule}
      @links[protocol] << edge(protocol, rule)
      return
    end

    min0 = rules.min_by? { |other| (rule.mid - other.mid).magn }
    if rules.size > 3
      min1 = rules.reject(min0).min_by? { |other| (rule.mid - other.mid).magn }
    end

    rules << rule

    # Find friends -- rules before & after the inserted rule,
    # therefore, the closest rules by the X position.
    friends = Set(RuleAgent).new
    friends << min0 if min0
    friends << min1 if min1

    # Keep friends close.
    friends.each do |friend|
      @links[protocol] << keep_close(rule, friend)
    end

    # Keep everyone else away.
    rules.each do |other|
      next if other.in?(friends) || other.same?(rule)

      @links[protocol] << keep_away(rule, other)
    end

    @links[protocol] << edge(protocol, rule)
  end

  # Breaks and removes all edges *agent* formed or currently participates in.
  #
  # This method does not dismiss (or remove) *agent* -- it only breaks
  # all connections of *agent* with other agents in this graph.
  def disconnect(agent : Agent)
    case agent
    when RuleAgent
      # Remove all mentions of the rule from the graph.
      @edges.each do |edge|
        next unless edge.any?(agent)

        # Edge removes itself from the graph when it
        # is dismissed.
        edge.dismiss
      end

      @graph.transform_values! &.reject(agent).to_set

      return
    when ProtocolAgent
      # Remove all connections possibly introduced by the removed
      # protocol to the graph.
      return unless @graph.has_key?(agent)

      @links[agent].each &.dismiss

      @links.delete(agent)
      @graph.delete(agent)
    end
  end
end
