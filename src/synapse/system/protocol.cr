record Message, keyword : String, args : Array(Memorable)

alias MemorableValue = Bool | Float64 | Lua::Table | String | Nil
alias Memorable = OwnedProtocol | PackedProtocol | MemorableValue

# Raised when a receiver cell wants to commit suicide.
class CommitSuicide < Exception
end

abstract struct RuleSignature
  def matches?(other : RuleSignature)
    false
  end
end

struct HeartbeatRuleSignature < RuleSignature
  getter? period : Time::Span?

  def initialize(@period : Time::Span?)
  end

  def matches?(message : Message)
    false
  end

  def matches?(other : HeartbeatRuleSignature)
    super || (period? == other.period?)
  end

  def to_agent(protoplasm : Protoplasm, instant : BufferEditorColumnInstant)
    agent = HeartbeatRuleAgent.new(protoplasm)
    agent.drain(instant)
    agent
  end
end

struct KeywordRuleSignature < RuleSignature
  def initialize(@keyword : String, @params : Array(String))
  end

  def matches?(message : Message)
    @keyword == message.keyword && @params.size == message.args.size
  end

  def matches?(other : KeywordRuleSignature)
    super || (@keyword == other.@keyword && @params == other.@params)
  end

  def to_agent(protoplasm : Protoplasm, instant : BufferEditorColumnInstant)
    agent = KeywordRuleAgent.new(protoplasm)
    agent.drain(instant)
    agent
  end

  def_clone
end

abstract struct Rule
  def initialize(@code : String)
  end

  def matches?(message : Message)
    false
  end

  def matches?(other : Rule)
    @code == other.@code
  end
end

struct BirthRule < Rule
  def express(agent : BirthRuleAgent, receiver : CellAvatar)
    receiver.interpret(result(agent, receiver))
  end

  def result(agent : BirthRuleAgent, receiver : CellAvatar) : ExpressionResult
    stack = Lua::Stack.new

    res = BirthExpressionContext.new(agent, receiver)
    res.fill(stack)

    begin
      stack.run(@code, "birth")

      OkResult.new
    rescue e : Lua::LuaError
      ErrResult.new(e, agent)
    rescue e : ArgumentError
      ErrResult.new(e, agent)
    ensure
      stack.close
    end
  end

  def to_agent(protoplasm : Protoplasm, instant : BufferEditorColumnInstant)
    agent = BirthRuleAgent.new(protoplasm)
    agent.drain(instant)
    agent
  end

  def_clone
end

abstract struct SignatureRule < Rule
  def initialize(@signature : RuleSignature, code)
    super(code)
  end

  def matches?(message : Message)
    @signature.matches?(message)
  end

  def matches?(other : Rule)
    false
  end

  def matches?(other : SignatureRule)
    @signature.matches?(other.@signature)
  end

  def to_agent(protoplasm : Protoplasm, instant : BufferEditorColumnInstant)
    @signature.to_agent(protoplasm, instant)
  end
end

abstract struct ExpressionResult
end

record OkResult < ExpressionResult
record ErrResult < ExpressionResult, error : Lua::LuaError | ArgumentError, agent : RuleAgent

struct KeywordRule < SignatureRule
  def matches?(vesicle : Vesicle) : Bool
    @signature.matches?(vesicle.message)
  end

  def result(agent : KeywordRuleAgent, receiver : CellAvatar, vesicle : Vesicle) : ExpressionResult
    # Attack is a heading pointing towards the vesicle.
    delta = (vesicle.mid - receiver.mid)
    attack = Math.atan2(-delta.y, delta.x)

    stack = Lua::Stack.new

    ctx = VesicleExpressionContext.new(agent, receiver, vesicle, attack)
    ctx.fill(stack)

    @signature.as(KeywordRuleSignature).@params.zip(vesicle.message.args) do |param, arg|
      stack.set_global(param, arg)
    end

    begin
      stack.run(@code, @signature.as(KeywordRuleSignature).@keyword)
      OkResult.new
    rescue e : Lua::LuaError
      ErrResult.new(e, agent)
    rescue e : ArgumentError
      ErrResult.new(e, agent)
    ensure
      stack.close
    end
  end

  def express(agent : KeywordRuleAgent, receiver : CellAvatar, vesicle : Vesicle)
    receiver.interpret(result(agent, receiver, vesicle))
  end
end

struct HeartbeatRule < SignatureRule
  def express(agent : HeartbeatRuleAgent, receiver : CellAvatar)
    stack = Lua::Stack.new

    # TODO: heartbeatresponsecontext, mainly to change period dynamically
    res = ExpressionContext.new(agent, receiver)
    res.fill(stack)

    begin
      stack.run(@code, "heartbeat:#{@signature.as(HeartbeatRuleSignature).period? || "tick"}")
      result = OkResult.new
    rescue e : Lua::LuaError
      result = ErrResult.new(e, agent)
    rescue e : ArgumentError
      result = ErrResult.new(e, agent)
    ensure
      stack.close
    end

    receiver.interpret(result)
  end
end

# Owned protocols are Lua references to protocols during rule
# expression, namely to protocols that the receiver cell *owns*,
# and therefore can control.
class OwnedProtocol
  include LuaCallable

  def initialize(@name : String, @protocol : ProtocolAgent)
  end

  # Returns the protocol that is owned.
  def _protocol
    @protocol
  end

  # Returns the name of this protocol.
  #
  # Synopsis:
  #
  # * `OP.name` where *OP* is the owned protocol.
  def name
    @name
  end

  # Enables this protocol.
  #
  # Synopsis:
  #
  # * `OP.enable` where *OP* is the owned protocol.
  def enable
    @protocol.enable
  end

  # Disables this protocol.
  #
  # Synopsis:
  #
  # * `OP.disable` where *OP* is the owned protocol.
  def disable
    @protocol.disable
  end

  # Toggles this protocol on/off.
  #
  # Synopsis:
  #
  # * `OP.toggle` where *OP* is the owned protocol.
  def toggle
    @protocol.toggle
  end

  # Switches this protocol on/off depending on *state*.
  #
  # `true` means this protocol is going to be enabled.
  # `false` means this protocol is going to be disabled.
  #
  # Synopsis:
  #
  # * `OP.switch(state : boolean)` where *OP* is the owned protocol.
  def switch(state : Bool)
    state ? enable : disable
  end
end

# Packed protocols are Lua references to protocols coming from/
# packaged in messages.
#
# They are already have no connection with the sender. They
# require the receiver cell to `adhere(packed protocol)` to
# them explicitly.
class PackedProtocol
  include LuaCallable

  def initialize(@name : String, @enabled : Bool, @ruleset : Hash(Rule, BufferEditorColumnInstant))
  end

  # Returns the name of the underlying protocol.
  #
  # Synopsis:
  #
  # * `PP.name` where *PP* is the packed protocol of interest.
  def name
    @name
  end

  # Asks *receiver* to adhere to this packed protocol.
  def _adhere(receiver : CellAvatar)
    receiver.adhere(@name, @enabled, @ruleset)
  end
end
