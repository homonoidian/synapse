struct Time::Span
  def clone
    self
  end
end

class SF::Clock
  def clone # Crap crap crap. Refer to FIXME (1) in this file (a bit below).
    self
  end
end

struct UUID # Crap crap crap. Crap!
  def clone
    self
  end
end

abstract class RuleSignature
end

class HeartbeatRuleSignature < RuleSignature
  getter? period : Time::Span?

  def initialize(@period : Time::Span?)
  end

  def matches?(message : Message)
    false
  end

  def append_rule(code : String, into editor : CellEditor)
    state = HeartbeatRuleEditorState.new

    if period = @period
      header = state.selected # Rule header
      header.split(backwards: false)
      header.selected.insert("#{period.total_milliseconds.to_i}ms")
    end

    unless code.empty?
      state.split(backwards: false)
      state.selected.selected.insert(code)
    end

    rule = HeartbeatRuleEditor.new(state, HeartbeatRuleEditorView.new)
    editor.append(rule)

    rule
  end

  def_clone
end

class KeywordRuleSignature < RuleSignature
  def initialize(@keyword : String, @params : Array(String))
  end

  def matches?(message : Message)
    @keyword == message.keyword && @params.size == message.args.size
  end

  def append_rule(code : String, into editor : CellEditor)
    state = KeywordRuleEditorState.new

    header = state.selected # Rule header
    header.selected.insert(@keyword)

    @params.each do |param|
      header.split(backwards: false)
      header.selected.insert(param)
    end

    unless code.empty?
      state.split(backwards: false)
      state.selected.selected.insert(code)
    end

    rule = KeywordRuleEditor.new(state, KeywordRuleEditorView.new)
    editor.append(rule)

    rule
  end

  def_clone
end

abstract class Rule
  def initialize(@code : String)
  end

  def matches?(message : Message)
    false
  end
end

class BirthRule < Rule
  def express(receiver : Cell, in tank : Tank)
    receiver.interpret(result(receiver), in: tank)
  end

  def result(receiver : Cell) : ExpressionResult
    stack = Lua::Stack.new

    res = BirthExpressionContext.new(receiver)
    res.fill(stack)

    begin
      stack.run(@code, "birth")

      OkResult.new
    rescue e : Lua::LuaError
      ErrResult.new(e, self)
    rescue e : ArgumentError
      ErrResult.new(e, self)
    ensure
      stack.close
    end
  end

  def append(into editor : CellEditor)
    state = BirthRuleEditorState.new
    state.code?.try &.insert(@code)
    rule = BirthRuleEditor.new(state, BirthRuleEditorView.new)
    editor.append(rule)

    rule
  end

  def_clone
end

abstract class SignatureRule < Rule
  def initialize(@signature : RuleSignature, code)
    super(code)
  end

  def matches?(message : Message)
    @signature.matches?(message)
  end

  def append(into editor : CellEditor)
    @signature.append_rule(@code, into: editor)
  end
end

abstract struct ExpressionResult
end

record OkResult < ExpressionResult
record ErrResult < ExpressionResult, error : Lua::LuaError | ArgumentError, rule : Rule do
  def index
    rule.index
  end
end

module RuleExpressibleFromVesicle
  abstract def express(receiver : Cell, vesicle : Vesicle, in tank : Tank)
  abstract def matches?(vesicle : Vesicle) : Bool
end

class KeywordRule < SignatureRule
  include RuleExpressibleFromVesicle

  def matches?(vesicle : Vesicle) : Bool
    @signature.matches?(vesicle.message)
  end

  def result(receiver : Cell, message : Message, attack = 0.0) : ExpressionResult
    stack = Lua::Stack.new

    ctx = MessageExpressionContext.new(receiver, message, attack)
    ctx.fill(stack)

    @signature.as(KeywordRuleSignature).@params.zip(message.args) do |param, arg|
      stack.set_global(param, arg)
    end

    begin
      stack.run(@code, @signature.as(KeywordRuleSignature).@keyword)
      result = OkResult.new
    rescue e : Lua::LuaError
      result = ErrResult.new(e, self)
    rescue e : ArgumentError
      result = ErrResult.new(e, self)
    ensure
      stack.close
    end
  end

  def express(receiver : Cell, vesicle : Vesicle, in tank : Tank)
    # Attack is a heading pointing towards the vesicle.
    delta = (vesicle.mid - receiver.mid)
    attack = Math.atan2(-delta.y, delta.x)
    result = result(receiver, vesicle.message, attack)
    receiver.interpret(result, in: tank)
  end

  def_clone
end

class HeartbeatRule < SignatureRule
  def initialize(signature, code)
    super

    @clock = SF::Clock.new # FIXME (1): THIS DOES NOT BELONG HERE!!!

    # NOTE: (1) This should be managed by a Heart object which a Cell owns!
    #           Heart could listen to changes in ProtocolCollection and traverse
    #           the heartbeat rules accordingly -- ask each HeartbeatRule to add
    #           itself with the expected period
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
  def systole(for receiver : Cell, in tank : Tank)
    # If heartbeat message was decided corrupt, then it shall
    # not be run.
    return if @corrupt

    if period = @signature.as(HeartbeatRuleSignature).period?
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
        stack.run(@code, "heartbeat:#{period}")
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

    receiver.interpret(result, in: tank)
  end

  # Dyastole resets heartbeat rules.
  def dyastole(for receiver : Cell, in tank : Tank)
    return unless period = @signature.as(HeartbeatRuleSignature).period?
    return unless lapses(period)

    @clock.restart
  end

  def_clone
end

class Protocol
  getter? enabled : Bool

  def initialize(@uid : UUID, @name : String?, @enabled : Bool)
    @rules = [] of Rule
  end

  # Enables this protocol.
  def enable
    @enabled = true
  end

  # Disables this protocol.
  def disable
    @enabled = false
  end

  # Toggles this protocol on/off.
  def toggle
    @enabled = !@enabled
  end

  # Yields rules in this protocol.
  def each_rule(&)
    @rules.each do |rule|
      yield rule
    end
  end

  # Yields heartbeat rules in this protocol.
  def each_heartbeat(&)
    each_rule do |rule|
      next unless rule.is_a?(HeartbeatRule)
      yield rule
    end
  end

  # Yields birth rules in this protocol.
  def each_birth_rule(&)
    each_rule do |rule|
      next unless rule.is_a?(BirthRule)
      yield rule
    end
  end

  # Yields all rules that are expressible from and match the given *vesicle*.
  def each_rule_matching(vesicle : Vesicle, &)
    each_rule do |rule|
      next unless rule.is_a?(RuleExpressibleFromVesicle)
      next unless rule.matches?(vesicle)
      yield rule
    end
  end

  # Adds *rule* to this protocol.
  def append(rule : Rule)
    @rules << rule
  end

  # Adds this protocol to *collection*.
  def append(*, into collection : ProtocolCollection)
    collection.assign(@uid, self)
  end

  def append(*, into collection : ProtocolsByName)
    return unless name = @name

    if set = collection[name]?
      set << self
    else
      collection[name] = Set{self}
    end
  end

  def append(*, into editor : CellEditor)
    #
    # Create and append a protocol editor.
    #
    state = ProtocolEditorState.new(@uid, @enabled)
    if name = @name
      state.selected.insert(name)
    end

    protocol = ProtocolEditor.new(state, ProtocolEditorView.new)

    editor.append(protocol)

    #
    # Create and append rule editors.
    #
    each_rule do |rule|
      appended = rule.append(into: editor)

      editor.connect(protocol, appended)
    end
  end

  def_equals_and_hash @uid
  def_clone
end

alias ProtocolsByName = Hash(String, Set(Protocol))

class ProtocolCollection
  def initialize
    @protocols = {} of UUID => Protocol
    @protocols_by_name = ProtocolsByName.new
  end

  # Returns the protocol with the given *id*, or nil.
  def []?(id : UUID) : Protocol?
    @protocols[id]?
  end

  # Yields each protocol in this collection regardless of whether it
  # is enabled.
  def each_protocol(&)
    @protocols.each_value do |protocol|
      yield protocol
    end
  end

  # Yields currently enabled protocols.
  def each_enabled_protocol(&)
    each_protocol do |protocol|
      next unless protocol.enabled?
      yield protocol
    end
  end

  # Yields each named protocol followed by its name regardless of whether
  # it is enabled.
  def each_named_protocol(&)
    @protocols_by_name.each do |name, protocols|
      protocols.each do |protocol|
        yield protocol, name
      end
    end
  end

  # Yields each currently enabled named protocol followed by its name.
  def each_enabled_named_protocol(&)
    each_named_protocol do |protocol, name|
      next unless protocol.enabled?
      yield protocol, name
    end
  end

  # Expresses rules matching *vesicle* in all enabled protocols.
  #
  # *receiver* is the receiver cell of expression.
  #
  # *tank* is the tank where *receiver* and *vesicle* reside.
  #
  # See `Protocol#express`.
  def express(receiver : Cell, vesicle : Vesicle, in tank : Tank)
    each_enabled_protocol &.each_rule_matching(vesicle, &.express(receiver, vesicle, in: tank))
  end

  # Expresses birth rules in all enabled protocols.
  #
  # *receiver* is the receiver cell of expression.
  #
  # *tank* is the tank where the *receiver* cell was born.
  def born(receiver : Cell, in tank : Tank)
    each_enabled_protocol &.each_birth_rule(&.express(receiver, in: tank))
  end

  @_systole_heartbeats = [] of HeartbeatRule

  # Expresses heartbeat rules in all enabled protocols.
  #
  # *receiver* is the receiver cell of expression.
  #
  # *tank* is the tank where *receiver* resides.
  def systole(receiver : Cell, in tank : Tank)
    @_systole_heartbeats.clear

    each_enabled_protocol do |protocol|
      protocol.each_heartbeat do |heartbeat|
        # To make sure a dyastole() is run only for, and for all systole()d
        # heartbeat rules, we have to store the heartbeat rules we systole()d
        # so as to dyastole() them later.
        @_systole_heartbeats << heartbeat

        heartbeat.systole(for: receiver, in: tank)
      end
    end
  end

  # Cleans up after heartbeat rules were run in `systole`.
  #
  # *receiver* is the receiver cell for which `systole` was run already.
  #
  # *tank* is the tank where *receiver* resides.
  def dyastole(receiver : Cell, in tank : Tank)
    @_systole_heartbeats.each &.dyastole(for: receiver, in: tank)
    @_systole_heartbeats.clear
  end

  # Invoked when instance memory of *receiver* changes.
  def on_memory_changed(receiver : Cell)
  end

  # Appends the given *protocol* to this collection.
  def summon(protocol : Protocol)
    protocol.append(into: self)
  end

  # Adds *protocol* to this collection, assigning it the given *id*.
  #
  # Will overwrite the protocol with the same id, if any.
  def assign(id : UUID, protocol : Protocol)
    @protocols[id] = protocol
    protocol.append(into: @protocols_by_name)
    protocol
  end

  def append(*, into editor : CellEditor)
    each_protocol &.append(into: editor)
  end
end

# Owned protocols are Lua references to protocols during rule
# expression, namely to protocols that the receiver cell *owns*,
# and therefore can control.
class OwnedProtocol
  include LuaCallable

  def initialize(@name : String, @protocol : Protocol)
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

  # For internal use only (not accessible from Lua).
  #
  # Clones the underlying protocol object, and returns the `PackedProtocol`
  # which wraps the clone.
  def _pack
    PackedProtocol.new(@name, @protocol.clone)
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

  def initialize(@name : String, @protocol : Protocol)
  end

  # Returns the name of the underlying protocol.
  #
  # Synopsis:
  #
  # * `PP.name` where *PP* is the packed protocol of interest.
  def name
    @name
  end

  # Asks *receiver* to accept this packed protocol, that is,
  # to start adhering to it.
  def _accept(receiver : Cell)
    receiver.accept(@protocol)
  end
end
