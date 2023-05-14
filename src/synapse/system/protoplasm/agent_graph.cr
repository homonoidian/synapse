# `AgentGraph` keeps track of how different `Agent`s relate to each other
# in a `Protoplasm`.
class AgentGraph
  def initialize(@protoplasm : Protoplasm)
    # Maps protocol agents to rule agents for e.g. rule lookup.
    @graph = {} of ProtocolAgent => Set(RuleAgent)

    # Maps protocol agents to *all* constraints they've created so
    # that they can be cleaned up when the protocol is removed.
    @links = {} of ProtocolAgent => Set(AgentAgentConstraint)

    # A set of *all* edges in the graph *including* those in @links.
    @edges = Set(AgentEdge).new
  end

  # Yields rules of the given *protocol* in no particular order.
  # Does nothing if *protocol* is not a vertex of this graph.
  def each_rule(*, of protocol : ProtocolAgent, &)
    return unless rules = @graph[protocol]?

    rules.each do |rule|
      yield rule
    end
  end

  # Yields protocols the given *rule* is a member of in no
  # particular order.
  def each_protocol(*, of rule : RuleAgent, &)
    @graph.each do |protocol, rules|
      rules.each do |other|
        next unless rule.same?(other)

        yield protocol
      end
    end
  end

  # Yields *all* edges in this graph in no particular order. *All*
  # means including both `AgentAgentEdge`s and `AgentPointEdge`s.
  def each_edge(&)
    @edges.each do |edge|
      yield edge
    end
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
    @edges.any? { |edge| edge.is_a?(AgentAgentEdge) && edge.contains?(a, b) }
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
      edge(protocol, rule)
      return
    end

    min0 = rules.min_by { |other| (rule.mid - other.mid).magn }
    min1 = rules.reject(min0).min_by? { |other| (rule.mid - other.mid).magn }

    rules << rule

    # Find friends -- rules before & after the inserted rule,
    # therefore, the closest rules by the X position.
    friends = Set{min0}
    if min1
      friends << min1
    end

    # Keep friends close.
    friends.each do |friend|
      @links[protocol] << keep_close(rule, friend)
    end

    # Keep everyone else away.
    rules.each do |other|
      next if other.in?(friends) || other.same?(rule)

      @links[protocol] << keep_away(rule, other)
    end

    edge(protocol, rule)
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
        next unless edge.contains?(agent)

        # Edge removes itself from the graph when it
        # is dismissed.
        edge.dismiss
      end

      @graph.transform_values! &.reject(agent).to_set

      return
    when ProtocolAgent
      # Remove all connections possibly introduced by the removed
      # protocol to the graph.
      return unless rules = @graph[agent]?

      @links[agent].each &.dismiss

      @links.delete(agent)
      @graph.delete(agent)
    end
  end
end
