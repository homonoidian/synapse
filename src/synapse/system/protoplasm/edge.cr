# Agent-agent, agent-point, etc. edges of an `AgentGraph`.
module AgentEdge
  def initialize(@graph : AgentGraph)
  end

  # Specifies the color in which this edge should be painted.
  def color
    SF::Color.new(0x77, 0x77, 0x77)
  end

  # Yields `Agent` endpoints of this edge, in no particular order.
  abstract def each_agent(& : Agent ->)

  # Builds `SF::Vertex` objects corresponding to this edge and
  # appends them to *array*.
  abstract def draw(*, to array)

  # Returns agent endpoint of the given *type*, or nil if this
  # edge has no such endpoint.
  def find?(type : T.class) : T? forall T
    each_agent do |agent|
      next unless agent.is_a?(T)
      return agent
    end
  end

  # Returns whether any of the endpoints of this edge are equal
  # to *endpoint*. Equality is tested with `==`.
  def any?(endpoint : Agent)
    each_agent do |agent|
      return true if endpoint == agent
    end

    false
  end

  # Returns whether all *agents* are endpoints of this edge.
  def all?(*agents : Agent)
    agents.all? { |agent| any?(agent) }
  end

  # Configures *tank* so that the constraints of this edge are met.
  def constrain(tank : Tank)
  end

  # Undoes the configuration if *tank* introduced in `constrain`.
  def loosen(tank : Tank)
  end

  # Inserts this edge into the graph.
  def summon
    @graph.insert(self)
  end

  # Removes this edge from the graph.
  def dismiss
    @graph.remove(self)
  end
end

# An edge between an `Agent` and a point.
class AgentPointEdge
  include AgentEdge

  # Holds the location of the point.
  property point : Vector2

  def initialize(graph : AgentGraph, @agent : Agent, @point)
    super(graph)
  end

  def color
    SF::Color.new(0x43, 0x51, 0x80)
  end

  def each_agent(& : Agent ->)
    yield @agent
  end

  def draw(*, to array)
    array.append(SF::Vertex.new(@agent.mid.sf, color))
    array.append(SF::Vertex.new(@point.sf, color))
  end
end

# A `CP::Constraint`-powered edge between two `Agent`s.
abstract struct AgentAgentConstraint
  include AgentEdge

  @constraint : CP::Constraint

  def initialize(graph : AgentGraph, @a : Agent, @b : Agent)
    super(graph)

    @constraint = constraint
  end

  # Builds and returns the desired `CP::Constraint`.
  protected abstract def constraint : CP::Constraint

  # Returns whether this edge should be visible to the user.
  def visible?
    true
  end

  # Adds `CP::Constraint`s to *tank* matching this edge.
  def constrain(tank : Tank)
    tank.insert(@constraint)
  end

  # Removes `CP::Constraint`s introduced by this edge in `constrain`
  # from *tank*.
  def loosen(tank : Tank)
    tank.remove(@constraint)
  end

  def each_agent(& : Agent ->)
    yield @a
    yield @b
  end

  def draw(*, to array)
    return unless visible?

    array.append(SF::Vertex.new(@a.mid.sf, color))
    array.append(SF::Vertex.new(@b.mid.sf, color))
  end

  def_equals_and_hash @a, @b
end

# An edge between two `Agent`s.
struct AgentAgentEdge < AgentAgentConstraint
  def constraint : CP::Constraint
    @a.spring to: @b,
      length: 5 * Agent.radius,
      stiffness: 150,
      damping: 200
  end
end

# An invisible edge between two `Agent`s that keeps them close
# to each other.
struct KeepcloseLink < AgentAgentConstraint
  def constraint : CP::Constraint
    @a.spring to: @b,
      length: 10 * Agent.radius,
      stiffness: 100,
      damping: 200
  end

  def visible?
    false
  end
end

# An invisible edge between two `Agent`s that keeps them away
# from each other.
struct KeepawayLink < AgentAgentConstraint
  def constraint : CP::Constraint
    @a.slide_joint with: @b,
      min: 10 * Agent.radius,
      max: Float64::INFINITY
  end

  def visible?
    false
  end
end
