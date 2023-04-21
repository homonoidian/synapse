abstract struct ExpressionResult
end

record OkResult < ExpressionResult
record ErrResult < ExpressionResult, error : Lua::LuaError | ArgumentError, rule : Rule do
  def index
    rule.index
  end
end

# Raised when a receiver cell wants to commit suicide.
class CommitSuicide < Exception
end

# Rules are named bit of computer code, in Synapse of Lua code.
abstract class Rule
  def initialize(@lua : Excerpt)
  end

  def index
    @lua.start
  end
end

abstract class RuleSignature
end

class KeywordRuleSignature < RuleSignature
  getter keyword, arity

  def initialize(@keyword : String, @arity : Int32)
  end

  def_equals_and_hash keyword, arity
end

class HeartbeatRuleSignature < RuleSignature
  getter period

  def initialize(@period : Time::Span?)
  end

  def_equals_and_hash period
end

class WildcardSignature < RuleSignature
  getter arity

  def initialize(@arity : Int32)
  end

  def_equals_and_hash arity
end

class BirthRule < Rule
  def result(receiver : Cell, message : Message)
  end

  def signature(*, to signatures)
  end

  def update(for cell : Cell, newer : BirthRule)
    return self if same?(newer)
    return self if @lua == newer.@lua

    tmp = @lua

    @lua = newer.@lua

    # may happen if meaningless characters were added
    unless tmp.string == @lua.string
      express(cell)
    end

    self
  end

  def express(receiver : Cell)
    # on-birth must be rerun for every copy separately!
    receiver.each_relative do |cell|
      cell.interpret result(cell)
    end
  end

  def result(receiver : Cell) : ExpressionResult
    stack = Lua::Stack.new

    res = ExpressionContext.new(receiver)
    res.fill(stack)

    begin
      stack.run(@lua.string, "birth")

      OkResult.new
    rescue e : Lua::LuaError
      ErrResult.new(e, self)
    rescue e : ArgumentError
      ErrResult.new(e, self)
    ensure
      stack.close
    end
  end
end

class KeywordRule < Rule
  getter keyword

  def initialize(@keyword : Excerpt, @params : Array(Excerpt), lua : Excerpt)
    super(lua)

    @id = UUID.random
  end

  def bounds
    @keyword.start..@lua.end
  end

  def header_start
    @keyword.start
  end

  def index
    @keyword.start
  end

  def signature(*, to signatures)
    signatures << signature
  end

  def signature
    if keyword.string == "*"
      WildcardSignature.new(@params.size)
    else
      KeywordRuleSignature.new(@keyword.string, @params.size)
    end
  end

  def result(receiver : Cell, message : Message, attack = 0.0) : ExpressionResult
    stack = Lua::Stack.new

    res = MessageExpressionContext.new(receiver, message, attack)
    res.fill(stack)

    @params.zip(message.args) do |param, arg|
      stack.set_global(param.string, arg)
    end

    begin
      stack.run(@lua.string, @keyword.string)
      result = OkResult.new
    rescue e : Lua::LuaError
      result = ErrResult.new(e, self)
    rescue e : ArgumentError
      result = ErrResult.new(e, self)
    ensure
      stack.close
    end
  end

  def changed
  end

  def update(for cell : Cell, newer : KeywordRule)
    return newer unless @keyword == newer.@keyword
    return self if self == newer

    @params = newer.@params
    @lua = newer.@lua
    @id = UUID.random
    changed

    self
  end

  def express(receiver : Cell, vesicle : Vesicle, attack : Float64)
    result = result(receiver, vesicle.message, attack)
    receiver.interpret(result)
  end

  def_equals_and_hash @id
end

class HeartbeatRule < KeywordRule
  def initialize(keyword : Excerpt, lua : Excerpt, @period : Time::Span?)
    super(keyword, [] of Excerpt, lua)

    @clock = SF::Clock.new
  end

  def signature
    HeartbeatRuleSignature.new(@period)
  end

  @corrupt = false

  def changed
    @corrupt = false
  end

  # Returns the amount of *pending* lapses for this heartbeat
  # rule. Caps to *cap*.
  def lapses(period : Time::Span, cap = 4)
    delta = @clock.elapsed_time.as_milliseconds - period.total_milliseconds

    return unless delta >= 0

    # We might have missed some...
    lapses = (delta / period.total_milliseconds).trunc + 1

    Math.min(cap, lapses.to_i)
  end

  # Systole is the "body" of a cell's heartbeat: at systole,
  # heartbeat rules are triggered.
  def systole(for receiver : Cell)
    # If heartbeat message was decided corrupt, then it shall
    # not be run.
    return if @corrupt

    if period = @period
      return unless count = lapses(period)
    else
      count = 1
    end

    result = uninitialized ExpressionResult

    # Count is at all times at least = 1, therefore, result
    # will be initialized.
    count.times do
      break if @corrupt

      stack = Lua::Stack.new

      # TODO: heartbeatresponsecontext, mainly to change period dynamically
      res = ExpressionContext.new(receiver)
      res.fill(stack)

      begin
        stack.run(@lua.string, "heartbeat:#{@period}")
        result = OkResult.new
      rescue e : Lua::LuaError
        result = ErrResult.new(e, self)
      rescue e : ArgumentError
        result = ErrResult.new(e, self)
      ensure
        stack.close
      end

      @corrupt = result.is_a?(ErrResult)
    end

    result
  end

  # Dyastole resets heartbeat rules.
  def dyastole(for receiver : Cell)
    return unless period = @period
    return unless lapses(period)

    @clock.restart
  end
end

class Protocol
  def initialize
    @rules = {} of RuleSignature => KeywordRule
    @birth = BirthRule.new(Excerpt.new("", 0))
  end

  private def each_birth_rule
    if birth = @birth
      yield birth
    end
  end

  def each_keyword_rule # FIXME: make this private, currently ProtocolEditor needs this
    @rules.each_value do |kwrule|
      yield kwrule
    end
  end

  private def each_heartbeat_rule
    @rules.each_value do |rule|
      yield rule if rule.is_a?(HeartbeatRule)
    end
  end

  private def fetch?(signature : RuleSignature)
    @rules[signature]?.try { |rule| yield rule }
  end

  private def fetch?(signature : KeywordRuleSignature)
    @rules[signature]?.try { |rule| yield rule }
    @rules[WildcardSignature.new(signature.arity)]?.try { |rule| yield rule }
  end

  def on_memory_changed(cell : Cell)
    each_heartbeat_rule &.changed
  end

  def systole(cell : Cell, tank : Tank)
    each_heartbeat_rule do |hb|
      result = hb.systole(for: cell)
      if result.is_a?(ErrResult)
        cell.fail(result, in: tank)
      end
    end
  end

  def dyastole(cell : Cell, tank : Tank)
    each_heartbeat_rule &.dyastole(for: cell)
  end

  def update(for cell : Cell, newer : KeywordRule) # FIXME: callers shoudn't be aware of rules!
    fetch?(newer.signature) do |prev|
      @rules[newer.signature] = prev.update(cell, newer)
      return
    end

    @rules[newer.signature] = newer
  end

  def update(for cell : Cell, newer : BirthRule) # FIXME: callers shoudn't be aware of rules!
    @birth = @birth.update(cell, newer)
  end

  def rewrite(signatures : Set(RuleSignature)) # FIXME: callers shoudn't be aware of rule signatures!
    new_rules = {} of RuleSignature => KeywordRule

    # Get rid of those decls that are not in the signatures set.
    signatures.each do |signature|
      new_rules[signature] = @rules[signature]
    end

    @rules = new_rules
  end

  def express(receiver : Cell, vesicle : Vesicle)
    fetch?(KeywordRuleSignature.new(vesicle.keyword, vesicle.nargs)) do |rule|
      # Attack is a heading pointing hdg the vesicle.
      delta = (vesicle.mid - receiver.mid)
      attack = Math.atan2(-delta.y, delta.x)

      rule.express(receiver, vesicle, attack)
    end
  end

  def born(receiver : Cell)
    @birth.express(receiver)
  end
end
