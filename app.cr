# FUN FACT: objects can move using messages

require "lch"
require "lua"
require "uuid"
require "uuid/json"
require "json"
require "crsfml"
require "chipmunk"
require "chipmunk/chipmunk_crsfml"
require "colorize"
require "string_scanner"

require "./ext"
require "./line"
require "./buffer"
require "./buffer_editor"

FONT        = SF::Font.from_memory({{read_file("./fonts/code/scientifica.otb")}}.to_slice)
FONT_BOLD   = SF::Font.from_memory({{read_file("./fonts/code/scientificaBold.otb")}}.to_slice)
FONT_ITALIC = SF::Font.from_memory({{read_file("./fonts/code/scientificaItalic.otb")}}.to_slice)

FONT_UI        = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Regular.ttf")}}.to_slice)
FONT_UI_MEDIUM = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Medium.ttf")}}.to_slice)
FONT_UI_BOLD   = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Bold.ttf")}}.to_slice)

FONT.get_texture(11).smooth = false
FONT_BOLD.get_texture(11).smooth = false
FONT_ITALIC.get_texture(11).smooth = false

# https://www.desmos.com/calculator/bk3g3l6txg
def fmessage_amount(strength : Float)
  if strength <= 80
    1.8256 * Math.log(strength)
  elsif strength <= 150
    6/1225 * (strength - 80)**2 + 8
  else
    8 * Math.log(strength - 95.402)
  end
end

def fmessage_amount_to_strength(amount : Float)
  if amount < 8
    Math::E**((625 * amount)/1141)
  elsif amount < 32
    (35 * Math.sqrt(amount - 8))/Math.sqrt(6) + 80
  else
    Math::E**(amount/8) + 47701/500
  end
end

def fmessage_lifespan_ms(strength : Float)
  if strength <= 155
    2000 * Math::E**(-strength/60)
  elsif strength <= 700
    Math::E**(strength/100) + 146
  else
    190 * Math.log(strength)
  end
end

def fmessage_lifespan_ms_to_strength(lifespan_ms : Float)
  if lifespan_ms <= 151
    60 * Math.log(2000/lifespan_ms)
  elsif lifespan_ms <= 1242
    100 * Math.log(lifespan_ms - 146)
  else
    Math::E**(lifespan_ms/190)
  end
end

module Inspectable
  abstract def follow(in tank : Tank, view : SF::View) : SF::View
end

record Message, id : UUID, sender : UUID, keyword : String, args : Array(Memorable), strength : Float64, decay = 0.0

abstract class Entity
  include SF::Drawable

  getter id : UUID
  getter tt = TimeTable.new(App.time)

  @decay_task_id : UUID

  def initialize(@color : SF::Color, lifespan : Time::Span?)
    @id = UUID.random
    @tanks = [] of Tank

    return unless lifespan

    @decay_task_id = tt.after(lifespan) do
      @tanks.each { |tank| suicide(in: tank) }
    end
  end

  def self.z_index
    0
  end

  def z_index
    self.class.z_index
  end

  abstract def drawable

  def summon(in tank : Tank)
    @tanks << tank

    tank.insert(self)

    nil
  end

  def suicide(in tank : Tank)
    @tanks.delete(tank)

    tank.remove(self)

    nil
  end

  def sync
  end

  def tick(delta : Float, in tank : Tank)
    tt.tick

    sync
  end

  def draw(target, states)
    drawable.draw(target, states)
  end

  def draw(tank : Tank, target)
    target.draw(self)
  end

  abstract def includes?(other : Vector2)

  def_equals_and_hash @id
end

abstract class PhysicalEntity < Entity
  @body : CP::Body
  @shape : CP::Shape
  private getter drawable : SF::Shape

  def initialize(color : SF::Color, lifespan : Time::Span?)
    super(color, lifespan)

    @body = self.class.body
    @shape = self.class.shape(@body)
    @drawable = self.class.drawable(@color)
  end

  def width
    @drawable.global_bounds.width + @drawable.local_bounds.left
  end

  def height
    @drawable.global_bounds.height + @drawable.local_bounds.top
  end

  def self.mass
    10.0
  end

  def self.friction
    10.0
  end

  def self.elasticity
    0.4
  end

  def mid
    @body.position.x.at(@body.position.y)
  end

  def mid=(mid : Vector2)
    @body.position = mid.cp
    sync
    mid
  end

  def stop
    @body.velocity = 0.at(0).cp
  end

  def velocity
    @body.velocity.x.at(@body.velocity.y)
  end

  def velocity=(velocity : Vector2)
    @body.velocity = velocity.cp

    velocity
  end

  def includes?(other : Vector2)
    other.x.in?(mid.x - width//2..mid.x + width//2) &&
      other.y.in?(mid.y - height//2..mid.y + height//2)
  end

  def summon(in tank : Tank)
    super

    tank.insert(self, @body)
    tank.insert(self, @shape)

    nil
  end

  def suicide(in tank : Tank)
    super

    tank.remove(self, @body)
    tank.remove(self, @shape)

    nil
  end

  def sync
    @drawable.position = (mid - @shape.radius).sf
  end

  def smack(other : Entity, in tank : Tank)
  end
end

class RoundEntity < PhysicalEntity
  def self.body
    moment = CP::Circle.moment(mass, 0.0, radius)

    CP::Body.new(mass, moment)
  end

  def self.shape(body : CP::Body)
    shape = CP::Circle.new(body, radius)
    shape.friction = friction
    shape.elasticity = elasticity
    shape
  end

  def self.drawable(color : SF::Color)
    drawable = SF::CircleShape.new
    drawable.radius = radius
    drawable.fill_color = color
    drawable
  end

  def self.radius
    4
  end
end

class Vesicle < RoundEntity
  def initialize(
    @message : Message,
    impulse : Vector2,
    lifespan : Time::Span,
    color : SF::Color,
    @birth : Time::Span
  )
    super(color, lifespan)

    @body.apply_impulse_at_local_point(impulse.cp, CP.v(0, 0))
  end

  def self.z_index
    1
  end

  def message
    @message.copy_with(decay: @tt.progress(@decay_task_id))
  end

  delegate :keyword, to: @message

  def nargs
    @message.args.size
  end

  def self.radius
    0.5
  end

  def self.mass
    0.5
  end

  def self.friction
    0.7
  end

  def self.elasticity
    1.0
  end

  def smack(other : Cell, in tank : Tank)
    other.receive(self, tank)
  end
end

abstract struct EvalResult; end

record OkResult < EvalResult
record ErrResult < EvalResult, error : Lua::LuaError | ArgumentError, rule : Rule do
  def index
    rule.index
  end
end

class ResponseContext
  def initialize(@receiver : Cell)
    @strength = 120.0
  end

  # Computes *heading angle* (in degrees) from a list of angles
  # (in degrees) with an optional list of weights ([0; 1], sum
  # must be 1). Essentially circular mean and weighted circular
  # mean under one function.
  #
  # Synopsis:
  #
  # * `heading(...angles : number)`
  # * `heading(angles : numbers)`
  # * `heading(angles : numbers, weights : numbers)`
  def heading(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    unless stack.size > 0
      raise Lua::RuntimeError.new("heading(_): expected angles array and an optional weights array, or a list of angles")
    end

    # Use the angle list variant if the first argument is a number:
    # compute the circular mean of the angles on the stack.
    if stack.top.is_a?(Float64)
      sines = 0
      cosines = 0

      until stack.size == 0
        unless angle = stack.pop.as?(Float64)
          raise Lua::RuntimeError.new("heading(...angles): expected angle (in degrees), a number")
        end

        angle = Math.radians(angle)

        sines += Math.sin(angle)
        cosines += Math.cos(angle)
      end

      stack << Math.degrees(Math.atan2(sines, cosines))

      return 1
    end

    # Assume weights table is on top of the stack. Create and
    # populate the fweights (float weights) array. Ensure sum
    # is about 1.0 (± epsilon, for fp errors)
    if stack.size == 2
      weights = stack.pop

      unless weights.is_a?(Lua::Table)
        raise Lua::RuntimeError.new("heading(angles, weights?): weights must be an array of weights [0; 1]")
      end

      sum = 0

      fweights = weights.map do |_, weight|
        unless (weight = weight.as?(Float64)) && weight.in?(0.0..1.0)
          raise Lua::RuntimeError.new("heading(angles, weights?): weight must be a number [0; 1]")
        end

        sum += weight

        weight
      end

      eps = 0.0001
      unless (1.0 - sum).abs <= eps
        raise Lua::RuntimeError.new("heading(angles, weights?): weights sum must be equal to 1 (currently: #{sum})")
      end
    end

    # Assume angles table is on top of the stack. Convert each
    # angle to radians, and zip with weights on the fly.
    angles = stack.pop

    unless angles.is_a?(Lua::Table) && angles.size > 0
      raise Lua::RuntimeError.new("heading(angles, weights?): angles must be an array of at least one angle (in degrees)")
    end

    unless fweights.nil? || fweights.size == angles.size
      raise Lua::RuntimeError.new("heading(angles, weights?): angles array and weights array must be of the same length")
    end

    # The least expensive way to get rid of the nil.
    fweights ||= Tuple.new

    sines = 0
    cosines = 0

    angles.zip?(fweights) do |(_, angle), weight|
      unless angle = angle.as?(Float64)
        raise Lua::RuntimeError.new("heading(angles, weights?): angle (degrees) must be a number")
      end

      angle = Math.radians(angle)

      sines += (weight || 1) * Math.sin(angle)
      cosines += (weight || 1) * Math.cos(angle)
    end

    stack << Math.degrees(Math.atan2(sines, cosines))

    1
  end

  # Retrieves or assigns the strength of messages emitted by `send`
  # *in this response context*. Meaning strength is local to the
  # specific response.
  #
  # Synopsis:
  #
  # * `strength() : number`
  # * `strength(newStrength : number) : number`
  def strength(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    if stack.size == 1
      unless strength = stack.pop.as?(Float64)
        raise Lua::RuntimeError.new("strength(newStrength): newStrength must be a number")
      end
      @strength = strength
    end

    stack << @strength

    1
  end

  # Emits a message at the receiver. Strength can be assigned/
  # retrieved using `setStrength/getStength`.
  #
  # Synopsis:
  #
  # * `send(keyword : string)`
  # * `send(keyword : string, ...args : boolean|number|table|string|nil)`
  def send(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    if stack.size.zero?
      raise Lua::RuntimeError.new("send(keyword, ...args): keyword is required")
    end

    args = Array(Memorable).new(stack.size - 1)

    until stack.size == 1
      arg = stack.pop
      unless arg.is_a?(Memorable)
        raise Lua::RuntimeError.new("send(keyword, ...args): argument must be a boolean, number, table, string, or nil")
      end
      args.unshift(arg)
    end

    unless keyword = stack.pop.as?(String)
      raise Lua::RuntimeError.new("send(keyword): keyword must be a string")
    end

    @receiver.emit(keyword, args, @strength, color: Cell.color(l: 80, c: 70))

    1
  end

  # Assigns compass heading and speed to the receiver. Motion does
  # not continue forever; the receiver slowly stops due to its own
  # friction and due to the environment's damping. This slightly
  # resembles swimming, hence the name.
  #
  # Synopsis:
  #
  # * `swim(heading degrees : number, speed : number)`
  def swim(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    unless (speed = stack.pop.as?(Float64)) && (heading = stack.pop.as?(Float64))
      raise Lua::RuntimeError.new("expected two numbers in swim(heading degrees, speed)")
    end

    @receiver.swim(heading, speed)

    1
  end

  # Prints to editor console.
  def print(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)
    string = (1..stack.size).join('\t') { |index| stack[index] || "nil" }

    Console::INSTANCE.print string

    1
  end

  # Populates *stack* with globals related to this response context.
  def fill(stack : Lua::Stack)
    stack.set_global("self", @receiver.memory)
    stack.set_global("id", @receiver.id.to_s)
    stack.set_global("heading", ->heading(LibLua::State))
    stack.set_global("strength", ->strength(LibLua::State))
    # TODO: set lifespan manually or use strength->lifespan formula
    stack.set_global("send", ->send(LibLua::State))
    stack.set_global("swim", ->swim(LibLua::State))
    stack.set_global("print", ->print(LibLua::State))
  end
end

class MessageResponseContext < ResponseContext
  def initialize(receiver : Cell, @message : Message, @attack = 0.0)
    super(receiver)
  end

  def fill(stack : Lua::Stack)
    super

    stack.set_global("keyword", @message.keyword)
    stack.set_global("sender", @message.sender.to_s)
    stack.set_global("impact", @message.strength)
    stack.set_global("decay", @message.decay)

    stack.set_global("attack", Math.degrees(@attack))
    stack.set_global("evasion", Math.degrees(Math.opposite(@attack)))
  end
end

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
      answer(cell)
    end

    self
  end

  def answer(receiver : Cell)
    # on-birth must be rerun for every copy separately!
    receiver.each_relative do |cell|
      cell.interpret result(cell)
    end
  end

  def result(receiver : Cell) : EvalResult
    stack = Lua::Stack.new

    res = ResponseContext.new(receiver)
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

  def result(receiver : Cell, message : Message, attack = 0.0) : EvalResult
    stack = Lua::Stack.new

    res = MessageResponseContext.new(receiver, message, attack)
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

  def answer(receiver : Cell, vesicle : Vesicle, attack : Float64)
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

    result = uninitialized EvalResult

    # Count is at all times at least = 1, therefore, result
    # will be initialized.
    count.times do
      break if @corrupt

      stack = Lua::Stack.new

      # TODO: heartbeatresponsecontext, mainly to change period dynamically
      res = ResponseContext.new(receiver)
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
  getter id : UUID

  def initialize
    @id = UUID.random
    @rules = {} of RuleSignature => KeywordRule
    @birth = BirthRule.new(Excerpt.new("", 0))
  end

  def each_birth_rule
    if birth = @birth
      yield birth
    end
  end

  def each_keyword_rule
    @rules.each_value do |kwrule|
      yield kwrule
    end
  end

  def each_heartbeat_rule
    @rules.each_value do |rule|
      yield rule if rule.is_a?(HeartbeatRule)
    end
  end

  def update(for cell : Cell, newer : KeywordRule)
    fetch?(newer.signature) do |prev|
      @rules[newer.signature] = prev.update(cell, newer)
      return
    end

    @rules[newer.signature] = newer
  end

  def update(for cell : Cell, newer : BirthRule)
    @birth = @birth.update(cell, newer)
  end

  def fetch?(signature : RuleSignature)
    @rules[signature]?.try { |rule| yield rule }
  end

  def fetch?(signature : KeywordRuleSignature)
    @rules[signature]?.try { |rule| yield rule }
    @rules[WildcardSignature.new(signature.arity)]?.try { |rule| yield rule }
  end

  def rewrite(signatures : Set(RuleSignature))
    new_rules = {} of RuleSignature => KeywordRule

    # Get rid of those decls that are not in the signatures set.
    signatures.each do |signature|
      new_rules[signature] = @rules[signature]
    end

    @rules = new_rules
  end

  def answer(receiver : Cell, vesicle : Vesicle)
    fetch?(KeywordRuleSignature.new(vesicle.keyword, vesicle.nargs)) do |rule|
      # Attack is a heading pointing hdg the vesicle.
      delta = (vesicle.mid - receiver.mid)
      attack = Math.atan2(-delta.y, delta.x)

      rule.answer(receiver, vesicle, attack)
    end
  end

  def born(receiver : Cell)
    @birth.answer(receiver)
  end
end

# An excerpt with a beginning and an end. Keeps positional
# information in sync with the excerpt string.
#
# Note that in the excerpt range, the end point is excluded.
# That is, the excerpt range is [b; e)
record Excerpt, string : String, start : Int32 do
  # Returns the end index of this excerpt in the source string.
  def end : Int
    start + string.size
  end

  # Maps *index* in this excerpt to the corresponding index in
  # the source string.
  def map(index : Int) : Int
    start + index
  end

  # Removes whitespace from the left and right of this excerpt.
  # Adjusts positional information accordingly.
  def strip : Excerpt
    orig = string

    lstr = orig.lstrip
    rstr = lstr.rstrip

    Excerpt.new(
      string: rstr,
      start: start + (orig.size - lstr.size),
    )
  end

  # Concatenates this and *other* excerpts.
  #
  # *other* excerpt must start immediately after this excerpt.
  # That is, its beginning must be the same as this excerpt's
  # end. Otherwise, this method will raise.
  def +(other : Excerpt)
    unless other.start == self.end
      raise ArgumentError.new("'+': right bounded excerpt must follow the left bounded excerpt")
    end

    Excerpt.new(string + other.string, start)
  end
end

# Represents the result of parsing a block. It's optionally
# a rule, plus zero or more markers.
record ParseResult, rule : Rule? = nil, markers = [] of Marker do
  # A shorthand for an error result with no rule and a single
  # hint marker.
  def self.hint(offset : Int, message : String)
    new(markers: [Marker.hint(offset, message)])
  end

  # A shorthand for a success result with `KeywordRule` rule
  # and no markers.
  def self.keyword(keyword : Excerpt, params : Array(Excerpt), lua : Excerpt)
    new(rule: KeywordRule.new(keyword, params, lua))
  end

  # A shorthand for a success result with `HeartbeatRule` rule
  # and no markers.
  def self.heartbeat(keyword : Excerpt, lua : Excerpt, period : Time::Span? = nil)
    new(rule: HeartbeatRule.new(keyword, lua, period))
  end
end

# Blocks are intermediates between raw source and `Rule`s.
abstract struct Block
  # Tries to convert this block into the corresponding `Rule`.
  abstract def to_rule : ParseResult
end

# Birth blocks are implicit blocks that consist of code only,
# and are later converted into `BirthRule`s.
#
# ```synapse
# -- The following Lua code will be stored under the born
# -- block/born rule.
# x = 123
# y = 456
# z = "hello world"
#
# heartbeat |
#   -- And this is going to be stored under a rule block /
#   -- keyword rule (heartbeat)
#   x = x + 1
# ```
record BirthBlock < Block, code : Excerpt do
  def to_rule : ParseResult
    ParseResult.new rule: BirthRule.new(code)
  end
end

record RuleBlock < Block, header : Excerpt, code : Excerpt do
  def to_rule : ParseResult
    scanner = StringScanner.new(header.string)

    #
    # Parse message keyword.
    #
    # <messageKeyword> ::= <alpha> <alnum>*
    #
    start = header.map(scanner.offset)
    unless keyword = scanner.scan(/(?:[A-Za-z]\w*|\*)/)
      return ParseResult.hint(start, "I want keyword (aka message name) here!")
    end

    heartbeat = keyword == "heartbeat"
    keyword = Excerpt.new(keyword, start)

    if heartbeat
      #
      # Parse heartbeat. Heartbeat does not take parameters.
      # It's either a period or the pipe.
      #
      # <heartbeat> ::= "heartbeat" WS (<period> | "|")
      #
      start = header.map(scanner.offset)

      unless scanner.scan(/[ \t]+/)
        return ParseResult.hint(start, "I want whitespace here!")
      end

      start = header.map(scanner.offset)

      if number = scanner.scan(/[1-9][0-9]*/)
        start = header.map(scanner.offset)

        unless unit = scanner.scan(/m?s/)
          return ParseResult.hint(start, "I want a time unit here, either 'ms' (for milliseconds) or 's' (for seconds)")
        end

        case unit
        when "ms"
          period = number.to_i.milliseconds
        when "s"
          period = number.to_i.seconds
        end
      end

      result = ParseResult.heartbeat(keyword, code, period)
    else
      #
      # Parse message parameters. Parameters follow the keyword,
      # therefore, a leading whitespace is always expected.
      #
      # <params> ::= (WS <param>)*
      # <param> ::= <alpha> <alnum>*
      #
      start = header.map(scanner.offset)
      params = [] of Excerpt
      while param = scanner.scan(/[ \t]+(?:[A-Za-z]\w*)/)
        params << Excerpt.new(param, start).strip
        start = header.map(scanner.offset)
      end

      result = ParseResult.keyword(keyword, params, code)
    end

    #
    # Make sure that the pipe character itself is in the
    # right place.
    #
    unless scanner.scan(/[ \t]*\|/)
      return ParseResult.hint(header.map(scanner.offset), "I want space followed by pipe '|' here!")
    end

    result
  end
end

record Marker, color : SF::Color, offset : Int32, tally : Hash(String, Int32) do
  def initialize(color, offset, message : String)
    hash = Hash(String, Int32).new(0)

    initialize(color, offset, message.lines.tally_by(hash, &.itself))
  end

  def self.hint(offset, message)
    hint_color = SF::Color.new(0xFF, 0xCA, 0x28)
    new(hint_color, offset, message)
  end

  def message
    String.build do |io|
      tally.each do |line, count|
        io << line
        unless count == 1
          io << "(x" << count << ")"
        end
      end
    end
  end

  def stack(other : Marker)
    tally.merge!(other.tally) do |_, l, r|
      l + r
    end

    self
  end
end

alias MarkerCollection = Hash(Int32, Marker)

class ProtocolEditorState
  getter id : UUID             # TODO: remove
  property protocol : Protocol # TODO: remove
  property? sync : Bool        # TODO: remove
  getter bstate                # TODO: remove
  getter markers               # TODO: remove

  def initialize(@protocol, @bstate = BufferEditorState.new, @markers = MarkerCollection.new, @sync = true)
    @id = UUID.random
  end

  delegate :cursor, :cursor=, to: @bstate   # TODO: remove
  delegate :buffer, :buffer=, to: @bstate   # TODO: remove
  delegate :markers, :markers=, to: @bstate # TODO: remove
end

class ProtocolEditor
  include SF::Drawable

  getter state # TODO: remove

  def initialize(@cell : Cell, @state : ProtocolEditorState)
    @editor_view = BufferEditorView.new
    @editor = BufferEditor.new(@state.bstate, @editor_view)
  end

  def initialize(cell : Cell, protocol : Protocol)
    initialize(cell, ProtocolEditorState.new(protocol))
  end

  def initialize(cell : Cell, other : ProtocolEditor)
    initialize(cell, other.state)
  end

  # TODO: remove
  private delegate :protocol, :protocol=, to: @state
  # TODO: remove
  private delegate :markers, :markers=, to: @state
  # TODO: remove
  private delegate :sync?, :sync=, to: @state

  # Editor needs to be refreshed when protocoleditor is focused
  # because other cells that have the same protocol (copies) may
  # have altered it.
  def refresh
    @editor.refresh
  end

  def update
    before = @state.bstate.capture
    yield
    after = @state.bstate.capture

    unless before == after
      markers.clear

      parse(after.string)
    end
  end

  def unsync(err : ErrResult)
    # Signal that what's currently running is out of sync from
    # what's being shown.
    self.sync = false

    mark(SF::Color::Red, err.index, err.error.message || "lua error")
  end

  def mark(color : SF::Color, offset : Int32, message : String)
    mark Marker.new(color, offset, message)
  end

  def mark(marker : Marker)
    # FIXME: this is MarkerCollection business!
    if prev = markers[marker.offset]?
      marker = prev.stack(marker)
    end

    markers[marker.offset] = marker
  end

  # hack to get it working. this should be managed by the event/
  # focus system
  def editor_handle(buf, event : SF::Event::KeyPressed)
    return unless buf.focused?

    case event.code
    when .delete?
      action = BufferEditor::Action::Delete.new(wordstep: event.control)
    when .backspace?
      action = BufferEditor::Action::Delete.new(wordstep: event.control, translation: -1)
    when .enter?
      action = BufferEditor::Action::InsertNewline.new
    when .tab?
      action = BufferEditor::Action::InsertIndent.new
    when .left?
      action = BufferEditor::Action::ToLeftBound.new(wordstep: event.control)
    when .right?
      action = BufferEditor::Action::ToRightBound.new(wordstep: event.control)
    when .up?
      action = BufferEditor::Action::ToLineAbove.new
    when .down?
      action = BufferEditor::Action::ToLineBelow.new
    when .home?
      action = BufferEditor::Action::ToLineStart.new
    when .end?
      action = BufferEditor::Action::ToLineEnd.new
    when .c?
      return unless event.control

      action = BufferEditor::Action::ToClipboard.new
    when .v?
      return unless event.control

      action = BufferEditor::Action::FromClipboard.new
    else
      return
    end

    buf.execute(action)
  end

  def editor_handle(buf, event : SF::Event::TextEntered)
    return unless buf.focused?

    chr = event.unicode.chr

    return unless chr.printable?

    action = BufferEditor::Action::Insert.new(chr.to_s)
    buf.execute(action)
  end

  def editor_handle(buf, event)
  end

  def handle(event)
    update { editor_handle(@editor, event) }
  end

  def rules_in(source : String)
    stack = [BirthBlock.new(Excerpt.new("", 0))] of Block
    offset = 0
    results = [] of ParseResult

    source.each_line(chomp: false) do |line|
      excerpt = Excerpt.new(line, offset)
      offset += line.size
      content = excerpt.strip
      if content.string.ends_with?('|')
        results << stack.pop.to_rule
        stack << RuleBlock.new(content, Excerpt.new("", excerpt.end))
        next
      end
      top = stack.last
      stack[-1] = top.copy_with(code: top.code + excerpt)
    end

    stack.each do |block|
      results << block.to_rule
    end

    results
  end

  def parse(source : String)
    results = rules_in(source)
    signatures = Set(RuleSignature).new
    if results.empty?
      self.sync = true
      protocol.rewrite(signatures)
      return
    end

    error = false

    results.each do |result|
      if rule = result.rule
        rule.signature(to: signatures)
        protocol.update(for: @cell, newer: rule)
      else
        error = true
        result.markers.each do |marker|
          mark(marker)
        end
      end
    end

    self.sync = !error
    unless error
      protocol.rewrite(signatures)
    end
  end

  # **Warning**: invalid before the first draw.
  getter origin : Vector2 = 0.at(0)
  # **Warning**: invalid before the first draw.
  getter corner : Vector2 = 0.at(0)

  def draw(target, states)
    @origin = origin = @cell.mid + @cell.class.radius * 1.1

    @editor_view.position = (origin + 15.at(15)).sfi

    extent = @editor_view.size + SF.vector2f(30, 30)

    @corner = origin + Vector2.new(extent)

    sync_color = sync? ? SF::Color.new(0x81, 0xD4, 0xFA, 0x88) : SF::Color.new(0xEF, 0x9A, 0x9A, 0x88)
    sync_color_opaque = SF::Color.new(sync_color.r, sync_color.g, sync_color.b)

    #
    # Draw line from origin of editor to center of cell.
    #
    va = SF::VertexArray.new(SF::Lines, 2)
    va.append(SF::Vertex.new(@cell.mid.sfi, sync_color_opaque))
    va.append(SF::Vertex.new(origin.sfi, sync_color_opaque))
    va.draw(target, states)

    #
    # Draw little circles at start of line to really show
    # which cell is selected.
    #
    start_circle = SF::CircleShape.new(radius: 2)
    start_circle.fill_color = sync_color_opaque
    start_circle.position = (@cell.mid - 2).sfi
    start_circle.draw(target, states)

    #
    # Draw background rectangle.
    #
    bg_rect = SF::RectangleShape.new
    bg_rect.fill_color = SF::Color.new(0x42, 0x42, 0x42, 0xbb)
    bg_rect.position = (origin + 5.at(1)).sfi
    bg_rect.outline_thickness = 1
    bg_rect.outline_color = sync_color # SF::Color.new(0x42, 0x42, 0x42, 0xee)
    bg_rect.size = extent - SF.vector2f(0, 2)
    bg_rect.draw(target, states)

    #
    # Draw thick left bar which shows whether the code is
    # synchronized with what's running.
    #
    bar = SF::RectangleShape.new
    bar.fill_color = sync_color
    bar.position = origin.sfi
    bar.size = SF.vector2f(4, extent.y)
    bar.draw(target, states)

    #
    # Underline every keyword rule. Keyword index and parameter
    # indices are assumed to be on the same line.
    #
    # If out of sync (errors occured), the underlines are not
    # drawn since the editor is probably in a bad state or they
    # would be drawn incorrectly anyway.
    #
    rule_headers = [] of SF::RectangleShape
    rule_header_bg = SF::Color.new(0x51, 0x51, 0x51)

    protocol.each_keyword_rule do |kwrule|
      next unless sync?

      b = kwrule.header_start

      b_pos = @editor_view.find_character_pos(b)

      h_bg = SF::RectangleShape.new
      h_bg.position = SF.vector2f(bg_rect.position.x, b_pos.y) + @editor_view.beam_margin
      h_bg.size = SF.vector2f(bg_rect.size.x, @editor_view.font_size)
      h_bg.fill_color = rule_header_bg

      h_sep_top = SF::RectangleShape.new
      h_sep_top.position = h_bg.position
      h_sep_top.size = SF.vector2f(h_bg.size.x, 1)
      h_sep_top.fill_color = SF::Color.new(0x61, 0x61, 0x61)

      h_sep_bot = SF::RectangleShape.new
      h_sep_bot.position = h_bg.position + SF.vector2f(0, h_bg.size.y)
      h_sep_bot.size = SF.vector2f(h_bg.size.x, 1)
      h_sep_bot.fill_color = SF::Color.new(0x61, 0x61, 0x61)

      rule_headers << h_bg
      rule_headers << h_sep_top
      rule_headers << h_sep_bot
    end

    rule_headers.each &.draw(target, states)

    @editor.draw(target, states)

    #
    # Draw markers
    #
    markers.each_value do |marker|
      coords = @editor_view.find_character_pos(marker.offset)

      # If cursor is below marker offset, we want this marker
      # to be above.
      m_line = state.bstate.index_to_line(marker.offset)
      c_line = state.bstate.line
      flip = c_line.ord > m_line.ord

      offset = SF.vector2f(0, @editor_view.line_height)
      coords += flip ? SF.vector2f(3, -3.5) : offset

      # To enable variation while maintaining uniformity with
      # the original color.
      l, c, h = LCH.rgb2lch(marker.color.r, marker.color.g, marker.color.b)

      bg_l = 70
      fg_l = 40

      mtext = SF::Text.new(marker.message, FONT, 11)

      mbg_rect_position = coords + (flip ? SF.vector2f(-6, -@editor_view.line_height - 0.2) : SF.vector2f(-3, 4.5))
      mbg_rect_size = SF.vector2f(
        mtext.global_bounds.width + mtext.local_bounds.left + 10,
        mtext.global_bounds.height + mtext.local_bounds.top + 4
      )

      #
      # Draw shadow rect for the marker text.
      #
      mshadow_rect = SF::RectangleShape.new
      mshadow_rect.position = mbg_rect_position + SF.vector2f(2, 2)
      mshadow_rect.size = mbg_rect_size
      mshadow_rect.fill_color = SF::Color.new(*LCH.lch2rgb(fg_l, c, h), 0x55)
      mshadow_rect.draw(target, states)
      @corner = @corner.max(Vector2.new(mshadow_rect.position + mshadow_rect.size))

      #
      # Draw the little triangle in the corner, pointing to the
      # marker offset.
      #
      tri = SF::CircleShape.new(radius: 3, point_count: 3)
      tri.fill_color = SF::Color.new(*LCH.lch2rgb(bg_l, c, h))
      tri.position = coords
      if flip
        tri.position += SF.vector2f(0, 4)
        tri.origin = SF.vector2f(3, 3)
        tri.rotate(180.0)
      end
      tri.draw(target, states)

      #
      # Draw background rectangle for the marker text.
      #
      mbg_rect = SF::RectangleShape.new
      mbg_rect.position = mbg_rect_position
      mbg_rect.size = mbg_rect_size
      mbg_rect.fill_color = SF::Color.new(*LCH.lch2rgb(bg_l, c, h))
      mbg_rect.draw(target, states)

      #
      # Draw marker text.
      #
      mtext.fill_color = SF::Color.new(*LCH.lch2rgb(fg_l, c, h))
      mtext.position = Vector2.new(mbg_rect.position + SF.vector2f(5, 2)).sfi
      mtext.draw(target, states)
    end
  end
end

alias Memorable = Bool | Float64 | Lua::Table | String | Nil

class Cell < RoundEntity
  include Inspectable

  class InstanceMemory
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

  getter memory : InstanceMemory do
    InstanceMemory.new(self)
  end

  @wires = Set(Wire).new

  def initialize
    super(self.class.color, lifespan: nil)

    @protocol = Protocol.new

    @relatives = [] of Cell

    @editor = uninitialized ProtocolEditor
    @editor = ProtocolEditor.new(self, @protocol)

    @relatives << self
  end

  def initialize(color : SF::Color, @protocol : Protocol, editor : ProtocolEditor, @relatives : Array(Cell))
    super(color, lifespan: nil)

    @editor = uninitialized ProtocolEditor
    @editor = ProtocolEditor.new(self, editor)
  end

  def copy
    copy = Cell.new(@color, @protocol, @editor, @relatives)
    @relatives << copy
    copy
  end

  def self.radius
    15
  end

  def self.mass
    100000.0 # TODO: WTF
  end

  SWATCH = (0..360).cycle.step(24)

  # Returns a random color.
  def self.color(l = 40, c = 50)
    hue = SWATCH.next
    until rand < 0.5
      hue = SWATCH.next
    end

    SF::Color.new *LCH.lch2rgb(l, c, hue.as(Int32))
  end

  def each_relative
    @relatives.each do |copy|
      yield copy
    end
  end

  def halo_color
    l, c, h = LCH.rgb2lch(@color.r, @color.g, @color.b)

    SF::Color.new(*LCH.lch2rgb(80, 50, h))
  end

  enum IRole
    Main
    Relative
  end

  def inspection_role?(in tank : Tank, is role : IRole? = nil) : IRole?
    each_relative do |relative|
      next unless tank.inspecting?(relative)

      relative_role = same?(relative) ? IRole::Main : IRole::Relative
      if role.nil? || relative_role == role
        return relative_role
      end
    end

    nil
  end

  def follow(in tank : Tank, view : SF::View) : SF::View
    return view unless inspection_role? in: tank, is: IRole::Main

    top_left = view.center - SF.vector2f(view.size.x/2, view.size.y/2)
    bot_right = top_left + view.size

    dx = 0
    dy = 0

    origin = @drawable.position - SF.vector2f(Cell.radius, Cell.radius)
    corner = @editor.corner.sf + SF.vector2f(Cell.radius, Cell.radius)
    extent = corner - origin

    if view.size.x < extent.x || view.size.y < extent.y
      # Give up: object doesn't fit into the view.
      return view
    end

    if origin.x < top_left.x # Cell is to the left of the view
      dx = origin.x - top_left.x
    elsif bot_right.x < corner.x # Cell is to the right of the view
      dx = corner.x - bot_right.x
    end

    if origin.y < top_left.y # Cell is above the view
      dy = origin.y - top_left.y
    elsif bot_right.y < corner.y # Cell is below the view
      dy = corner.y - bot_right.y
    end

    return view if dx.zero? && dy.zero?

    new_top_left = SF.vector2f(top_left.x + dx, top_left.y + dy)

    view.center = new_top_left + view.size/2
    view
  end

  def prn(message : String)
    @tanks.each &.prn(self, message)
  end

  def swim(heading : Float64, speed : Float64)
    @body.velocity = (Math.radians(heading).dir * 1.at(-1) * speed).cp
  end

  def add_wire(wire : Wire)
    @wires << wire
  end

  def sender_of?(message : Message)
    message.sender == @id
  end

  def emit(keyword : String, strength : Float64, color : SF::Color)
    emit(keyword, [] of Memorable, strength, color)
  end

  def emit(keyword : String, args : Array(Memorable), strength : Float64, color : SF::Color)
    message = Message.new(
      id: UUID.random,
      sender: @id,
      keyword: keyword,
      args: args,
      strength: strength,
    )

    @wires.each do |wire|
      wire.distribute(message, color)
    end

    @tanks.each do |tank|
      tank.distribute(mid, message, color)
    end
  end

  def interpret(result : EvalResult)
    return unless result.is_a?(ErrResult)

    @tanks.each do |tank|
      fail(result, tank)
    end
  end

  def summon(*, in tank : Tank)
    super
    @protocol.born(self)
    nil
  end

  def suicide(*, in tank : Tank)
    super

    @relatives.delete(self)

    nil
  end

  @handled = Set(UUID).new

  def receive(vesicle : Vesicle, in tank : Tank)
    return if vesicle.message.id.in?(@handled)

    @handled << vesicle.message.id
    @protocol.answer(receiver: self, vesicle: vesicle)
  end

  def fail(err : ErrResult, in tank : Tank)
    # On error, if nothing is being inspected, ask tank to
    # start inspecting myself.
    #
    # In any case, add a mark to where the Lua code of the
    # declaration starts.
    tank.inspect(self) if tank.inspecting?(nil)

    @editor.unsync(err)
  end

  def handle(event)
    @editor.handle(event)
  end

  def start_inspection?(in tank : Tank)
    @editor.refresh

    true
  end

  def stop_inspection?(in tank : Tank)
    true
  end

  def on_memory_changed
    # The success of heartbeat rules also depends on the memory.
    # If memory changed, try to rerun heartbeat rules.
    @protocol.each_heartbeat_rule &.changed
  end

  # Prefer using `Tank` to calling this method yourself because
  # sync of systoles/dyastoles between relatives is unsupported.
  def systole(in tank : Tank)
    @protocol.each_heartbeat_rule do |hb|
      result = hb.systole(for: self)
      if result.is_a?(ErrResult)
        fail(result, in: tank)
      end
    end
  end

  # :ditto:
  def dyastole(in tank : Tank)
    @protocol.each_heartbeat_rule &.dyastole(for: self)
  end

  def draw(tank : Tank, target)
    super

    return unless role = inspection_role? in: tank

    #
    # Draw halo
    #
    halo = SF::CircleShape.new
    halo.radius = Cell.radius * 1.15
    halo.position = (mid - halo.radius).sf
    halo.fill_color = SF::Color::Transparent
    halo.outline_color = SF::Color.new(halo_color.r, halo_color.g, halo_color.b, 0x88)
    halo.outline_thickness = 1.5
    target.draw(halo)

    if role.main?
      target.draw(@editor)
    end
  end
end

class Vein < PhysicalEntity
  def initialize
    super(SF::Color.new(0x61, 0x61, 0x61), lifespan: nil)
  end

  def self.body
    body = CP::Body.new_static
    body
  end

  def self.width
    10
  end

  def self.height
    720
  end

  def self.shape(body : CP::Body)
    shape = CP::Shape::Poly.new(body, [
      CP.v(body.position.x, height),
      CP.v(width, height),
      CP.v(width, body.position.y),
      body.position,
    ])
    shape.friction = friction
    shape.elasticity = elasticity
    shape
  end

  def self.drawable(color : SF::Color)
    drawable = SF::RectangleShape.new
    drawable.position = 0.at(0).sf
    drawable.size = width.at(height).sf
    drawable.fill_color = color
    drawable
  end

  def sync
  end

  def emit(keyword : String, args : Array(Memorable), color : SF::Color)
    message = Message.new(
      id: UUID.random,
      sender: @id,
      keyword: keyword,
      args: args,
      strength: 50,
    )

    # Distribute at each 5th heightpoint.
    0.step(to: self.class.height, by: 10) do |yoffset|
      @tanks.each &.distribute_vein_bi(mid + 0.at(yoffset), message, color, 400.milliseconds)
    end
  end
end

class Wire < Entity
  private getter drawable : SF::VertexArray

  def initialize(@src : Cell, @dst : Vector2)
    super(@src.halo_color, lifespan: nil)

    @drawable = SF::VertexArray.new(SF::Lines)
    @drawable.append(SF::Vertex.new(@src.mid.sf, @color))
    @drawable.append(SF::Vertex.new(@dst.sf, @color))
  end

  def self.z_index
    -1
  end

  def includes?(other : Vector2)
    false
  end

  def sync
    @drawable = SF::VertexArray.new(SF::Lines)
    @drawable.append(SF::Vertex.new(@src.mid.sf, @color))
    @drawable.append(SF::Vertex.new(@dst.sf, @color))
  end

  def distribute(message : Message, color : SF::Color)
    @tanks.each do |tank|
      tank.distribute(@dst, message, color, deadzone: 1)
    end
  end
end

class Actor
  include SF::Drawable

  def initialize
    @text = SF::Text.new("", FONT, 11)
    @text.fill_color = SF::Color::Black
  end

  def prn(string)
    @text.string += string
  end

  def draw(target, states)
    @text.draw(target, states)
  end
end

class Tank
  include SF::Drawable

  class TankDispatcher < CP::CollisionHandler
    def initialize(@tank : Tank)
      super()
    end

    def begin(arbiter : CP::Arbiter, space : CP::Space)
      ba, bb = arbiter.bodies

      return true unless a = @tank.find_entity_by_body?(ba)
      return true unless b = @tank.find_entity_by_body?(bb)

      a.smack(b, in: @tank)
      b.smack(a, in: @tank)

      true
    end
  end

  @inspecting : Inspectable?

  def initialize
    @space = CP::Space.new
    @space.damping = 0.3
    @space.gravity = CP.v(0, 0)

    @bodies = {} of UInt64 => PhysicalEntity
    @entities = {} of UUID => Entity
    @actors = [] of Actor

    @tt = TimeTable.new(App.time)

    dispatcher = TankDispatcher.new(self)

    @space.add_collision_handler(dispatcher)
  end

  def inspecting?(object : Inspectable?)
    @inspecting.same?(object)
  end

  def inspect(other : Inspectable?)
    ok = true

    # Ask the previously inspected entity on whether it wants
    # to stop being inspected.
    if prev = @inspecting
      ok &= prev.stop_inspection?(in: self)
    end

    # Ask the to-be-inspected entity on whether it wants to
    # start being inspected.
    ok &&= other.start_inspection?(in: self) if other

    @inspecting = other if ok

    other ? App.the.stop_time : App.the.start_time

    other
  end

  def prn(cell : Cell, message : String)
    @actors.each do |actor|
      actor.prn(message)
    end
  end

  def has_no_cells?
    each_cell { return false }

    true
  end

  def insert(entity : Entity, object : CP::Shape | CP::Body)
    @space.add(object)
    if object.is_a?(CP::Body)
      @bodies[object.object_id] = entity
    end
  end

  def insert(entity : Entity)
    @entities[entity.id] = entity
  end

  def insert(actor : Actor)
    @actors << actor
  end

  def remove(entity : Entity, object : CP::Shape | CP::Body)
    @space.remove(object)
    if object.is_a?(CP::Body)
      @bodies.delete(object.object_id)
    end
  end

  def remove(actor : Actor)
    @actors.delete(actor)
  end

  def remove(entity : Entity)
    @entities.delete(entity.id)
  end

  def cell(*, to pos : Vector2)
    cell = Cell.new
    cell.mid = pos
    cell.summon(in: self)
    cell
  end

  def vein(*, to pos : Vector2)
    vein = Vein.new
    vein.mid = pos
    vein.summon(in: self)
    vein
  end

  def wire(*, from cell : Cell, to pos : Vector2)
    wire = Wire.new(cell, pos)
    cell.add_wire(wire)
    wire.summon(in: self)
    wire
  end

  def each_actor
    @actors.each do |actor|
      yield actor
    end
  end

  def each_entity
    @entities.each_value do |entity|
      yield entity
    end
  end

  def each_entity_by_z_index
    entities = @entities.values.unstable_sort_by!(&.z_index)
    entities.each do |entity|
      yield entity
    end
  end

  def each_cell
    each_entity do |entity|
      yield entity if entity.is_a?(Cell)
    end
  end

  def each_vein
    each_entity do |entity|
      yield entity if entity.is_a?(Vein)
    end
  end

  def find_entity_by_id?(id : UUID)
    @entities[id]?
  end

  def find_entity_by_body?(body : CP::Body)
    @bodies[body.object_id]?
  end

  def find_cell_by_id?(id : UUID)
    find_entity_by_id?(id).as?(Cell)
  end

  def find_entity_at?(pos : Vector2)
    each_entity { |entity| return entity if pos.in?(entity) }
  end

  def find_cell_at?(pos : Vector2)
    find_entity_at?(pos).as?(Cell)
  end

  def distribute(origin : Vector2, message : Message, color : SF::Color, deadzone = Cell.radius * 1.2)
    vamt = fmessage_amount(message.strength)

    return unless vamt.in?(1.0..1024.0) # safety belt

    vrays = Math.max(1, vamt // 2)

    vamt = vamt.to_i
    vrays = vrays.to_i
    vlifespan = fmessage_lifespan_ms(message.strength).milliseconds

    vamt.times do |v|
      angle = Math.radians(((v / vrays) * 360) + rand * 360)
      impulse = angle.dir * (10.0..100.0).sample # FIXME: should depend on strength
      vesicle = Vesicle.new(message, impulse, vlifespan, color, birth: Time.monotonic)
      vesicle.mid = origin + (angle.dir * deadzone)
      vesicle.summon(in: self)
    end
  end

  def distribute_vein_bi(origin : Vector2, message : Message, color : SF::Color, lifespan : Time::Span)
    vamt = 2
    vrays = 2

    vamt.times do |v|
      angle = Math.radians(((v / vrays) * 360))
      impulse = angle.dir * message.strength
      vesicle = Vesicle.new(message, impulse, lifespan, color, birth: Time.monotonic)
      if v.even?
        vesicle.mid = origin + (angle.dir * Vein.width)
      else
        vesicle.mid = origin + angle.dir
      end
      vesicle.summon(in: self)
    end
  end

  def tick(delta : Float)
    @tt.tick
    @space.step(delta)
    each_entity &.tick(delta, in: self)
    # TODO: avoid going thru all entities thrice: segregate cells
    # into another collection?
    each_cell &.systole(in: self)
    each_cell &.dyastole(in: self)
  end

  def handle(event : SF::Event)
    @inspecting.try &.handle(event)
  end

  def follow(view : SF::View) : SF::View
    @inspecting.try &.follow(in: self, view: view) || view
  end

  def draw(target, states)
    # dd = SFMLDebugDraw.new(target, states)
    # dd.draw(@space)
  end

  def draw(what : Symbol, target : SF::RenderTarget)
    case what
    when :entities
      #
      # Draw entities ordered by their z index.
      #
      each_entity_by_z_index do |entity|
        next if entity == @inspecting

        entity.draw(self, target)
      end

      # Then draw the inspected entity. This is done so that
      # the inspected entity is in front, that is, drawn on
      # top of everything else.
      @inspecting.try &.draw(self, target)

      target.draw(self)
    when :actors
      each_actor { |actor| target.draw(actor) }
    end
  end
end

abstract class Mode
  include SF::Drawable

  def cursor(app : App)
    app.default_cursor
  end

  def load(app : App)
    app.editor_cursor = cursor(app)
  end

  def unload(app : App)
    app.editor_cursor = app.default_cursor
  end

  @mouse = Vector2.new(0, 0)
  @mouse_in_tank = Vector2.new(0, 0)

  def map(app, event : SF::Event::MouseMoved)
    @mouse = event.x.at(event.y)
    @mouse_in_tank = app.coords(event)
    self
  end

  # Maps *event* to the next mode.
  def map(app, event)
    app.tank.handle(event)

    self
  end

  # Holds the title and description of a mode.
  record ModeHint, title : String, desc : String

  # Returns the title and description of a mode.
  abstract def hint : ModeHint

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    gap_y = 8
    padding = 5

    title = SF::Text.new(hint.title, FONT_UI_BOLD, 16)
    title.position = SF.vector2f(padding, padding)
    title.color = SF::Color.new(0x3c, 0x30, 0x00)

    title_width = title.global_bounds.width + title.local_bounds.left
    title_height = title.global_bounds.height + title.local_bounds.top

    desc = SF::Text.new(hint.desc, FONT_UI, 11)
    desc.position = SF.vector2i(padding, title_height.to_i + gap_y + padding)
    desc.color = SF::Color.new(0x56, 0x46, 0x00)

    desc_width = desc.global_bounds.width + desc.local_bounds.left
    desc_height = desc.global_bounds.height + desc.local_bounds.top

    bg = SF::RectangleShape.new
    bg.size = SF.vector2f(
      Math.max(title_width, desc_width) + padding * 2,
      title_height + desc_height + gap_y + padding * 2
    )
    bg.fill_color = SF::Color.new(0xFF, 0xE0, 0x82)

    bounds = SF.float_rect(0, 0, target.size.x, target.size.y)

    # Do not draw if window is smaller than 1.5 * hint widths /
    # 3 * hint heights (height is more expensive)
    return unless bounds.contains?(bg.size * SF.vector2f(1.5, 3))

    offset = SF.vector2f(bounds.width - bg.size.x - 10, 10)

    bg.position += offset
    title.position += offset
    desc.position += offset

    bg.draw(target, states)
    title.draw(target, states)
    desc.draw(target, states)
  end

  def draw(app : App, target : SF::RenderTarget)
    return unless app.tank.inspecting?(nil)

    target.draw(self)
  end

  def tick(app)
  end
end

MOUSE_ID = UUID.random

class Mode::Normal < Mode
  def initialize(@elevated : Cell? = nil, @ondrop : Mode = self)
  end

  def hint : ModeHint
    ModeHint.new(
      title: "Normal mode",
      desc: <<-END
      Double click or start typing over empty space to add new
      cells and inspect them simultaneously. Move cells around
      by dragging them. Click on a cell to inspect it. Hit Esc to
      uninspect; then press Delete/Backspace to go into slaying
      mode. Note that this panel will disappear when you start
      inspecting.
      END
    )
  end

  def tick(app)
    super
    app.follow unless @elevated
  end

  def try_inspect(app, cell)
    app.tank.inspect(cell)
  end

  @clicks = 0
  @prev_button : SF::Mouse::Button?
  @clickclock : SF::Clock? = nil

  def map(app, event : SF::Event::MouseButtonPressed)
    coords = app.coords(event)

    if (cc = @clickclock) && cc.elapsed_time.as_milliseconds < 300 && event.button == @prev_button
      @clicks = 2
    else
      @clicks = 1
      @prev_button = event.button
    end

    @mouse = event.x.at(event.y)
    @mouse_in_tank = coords

    cc = @clickclock ||= SF::Clock.new
    cc.restart

    if @mouse_in_tank.in?(app.console) || app.console.elevated?
      app.console.handle(event, clicks: @clicks)
      return self
    end

    case event.button
    when .left?
      cell = app.tank.find_cell_at?(coords)
      case @clicks
      when 2
        # Create cell
        cell ||= app.tank.cell to: coords
      when 1
        # Inspect & elevate cell/void
      else
        return super
      end
      @elevated = cell
      try_inspect(app, cell)
    when .right?
      app.tank.distribute(coords, Message.new(
        id: UUID.random,
        sender: MOUSE_ID,
        keyword: "mouse",
        args: [] of Memorable,
        strength: (@clicks == 2 ? 250 : 130)
      ), SF::Color::White, deadzone: 1)
    end

    self
  end

  def map(app, event : SF::Event::MouseButtonReleased)
    if @elevated.nil? && (@mouse_in_tank.in?(app.console) || app.console.elevated?)
      app.console.handle(event)
      return self
    end

    @elevated.try &.stop
    @elevated = nil

    @ondrop
  end

  def map(app, event : SF::Event::MouseMoved)
    super

    if @elevated.nil? && (@mouse_in_tank.in?(app.console) || app.console.elevated?)
      app.console.handle(event)
      return self
    end

    @elevated.try do |cell|
      cell.mid = @mouse_in_tank
    end

    self
  end

  def map(app, event : SF::Event::MouseWheelScrolled)
    if @mouse_in_tank.in?(app.console) || app.console.elevated?
      app.console.handle(event)
      return self
    end

    app.pan(0.at(-event.delta * 10))

    self
  end

  def map(app, event : SF::Event::TextEntered)
    return super unless app.tank.inspecting?(nil)
    return super if app.tank.find_cell_at?(@mouse_in_tank)
    return super unless (chr = event.unicode.chr).alphanumeric?

    cell = app.tank.cell to: @mouse_in_tank
    try_inspect(app, cell)

    super
  end

  def map(app, event : SF::Event::KeyPressed)
    case event.code
    when .l_control?, .r_control?
      return Mode::Ctrl.new
    when .l_shift?, .r_shift?
      return Mode::Shift.new(WireConfig.new)
    when .escape?
      try_inspect(app, nil)
    when .delete?, .backspace?
      if app.tank.inspecting?(nil)
        return Mode::Slaying.new
      end
    when .space? # ANCHOR: Space :: toggle time
      if app.tank.inspecting?(nil)
        app.toggle_time
      end
    end
    super
  end
end

class Mode::Slaying < Mode
  def hint : ModeHint
    ModeHint.new(
      title: "Slaying mode",
      desc: <<-END
      Click on any cell to slay it. Hit Escape, Delete, or
      Backspace to quit.
      END
    )
  end

  def cursor(app : App)
    SF::Cursor.from_system(SF::Cursor::Type::Cross)
  end

  # Delete cell only if LMB was pressed AND released over it.

  @pressed_on : Cell?

  def map(app, event : SF::Event::MouseButtonPressed)
    return super unless event.button.left?

    coords = app.coords(event)

    @pressed_on = app.tank.find_cell_at?(coords)

    self
  end

  def map(app, event : SF::Event::MouseButtonReleased)
    coords = app.coords(event)

    case event.button
    when .left?
      released_on = app.tank.find_cell_at?(coords)
      if released_on && @pressed_on.same?(released_on)
        released_on.suicide(in: app.tank)
      end
    end

    app.tank.has_no_cells? ? Mode::Normal.new : self
  end

  def map(app, event : SF::Event::KeyPressed)
    case event.code
    when .escape?, .delete?, .backspace?
      return Mode::Normal.new
    end

    self
  end

  def map(app, event)
    self
  end
end

record WireConfig, from : Cell? = nil, to : Vector2? = nil

class Mode::Shift < Mode::Normal
  def initialize(@wire : WireConfig)
    super()
  end

  def hint : ModeHint
    ModeHint.new(
      title: "Shift-Mode",
      desc: <<-END
      Click on a cell/empty space to create a wire from/to
      where you clicked. Use mouse wheel to scroll horizontally.
      END
    )
  end

  def submit(app : App, src : Cell, dst : Vector2)
    app.tank.wire(from: src, to: dst)
  end

  def map(app, event : SF::Event::MouseWheelScrolled)
    app.pan((-event.delta * 10).at(0))

    self
  end

  def map(app, event : SF::Event::MouseButtonPressed)
    coords = app.coords(event)

    if (from = @wire.from) && (to = @wire.to)
      submit(app, from, to)

      @wire = WireConfig.new
    end

    if @wire.from.nil?
      cell = app.tank.find_cell_at?(coords)
      @wire = @wire.copy_with(from: cell)
    end

    if cell.nil? && @wire.to.nil?
      @wire = @wire.copy_with(to: coords)
    end

    if (from = @wire.from) && (to = @wire.to)
      submit(app, from, to)

      @wire = WireConfig.new
    end

    self
  end

  def map(app, event : SF::Event::KeyReleased)
    case event.code
    when .l_shift?, .r_shift?
      if (from = @wire.from) && (to = @wire.to)
        submit(app, from, to)
      end
      return Mode::Normal.new
    end

    super
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    super

    return unless @wire.from || @wire.to

    text = SF::Text.new("Please finish the wire by clicking somewhere...", FONT_UI, 18)
    text.fill_color = SF::Color.new(0x99, 0x99, 0x99)
    text_size = SF.vector2f(
      text.global_bounds.width + text.local_bounds.left,
      text.global_bounds.height + text.local_bounds.top,
    )

    text.position = Vector2.new(target.view.center - text_size/2).sfi
    text.draw(target, states)
  end
end

class Mode::Ctrl < Mode
  def hint : ModeHint
    ModeHint.new(
      title: "Ctrl-Mode",
      desc: <<-END
      Drag to pan around. Use mouse wheel to zoom. Click the
      middle mouse button to reset zoom. Use right mouse button
      to shallow-copy a cell.
      END
    )
  end

  def map(app, event : SF::Event::KeyReleased)
    return super unless event.code.l_control?

    Mode::Normal.new
  end

  def map(app, event : SF::Event::MouseButtonPressed)
    case event.button
    when .left?
      return Mode::Panning.new app.coords(event)
    when .middle?
      app.unzoom

      self
    when .right?
      coords = app.coords(event)
      if cell = app.tank.find_cell_at?(coords)
        copy = cell.copy
        copy.mid = coords
        copy.summon(in: app.tank)
        app.tank.inspect(copy)
        return Mode::Normal.new(elevated: copy, ondrop: self)
      end
    end
    self
  end

  def map(app, event : SF::Event::MouseWheelScrolled)
    app.zoom(event.delta < 0 ? 1.1 : 0.9)

    self
  end
end

class Mode::Panning < Mode::Ctrl
  def initialize(@origin : Vector2)
  end

  def hint : ModeHint
    ModeHint.new(
      title: "Pan mode",
      desc: <<-END
      Release the left mouse button when you've finished panning.
      END
    )
  end

  def map(app, event : SF::Event::MouseButtonReleased)
    return super unless event.button.left?

    Mode::Ctrl.new
  end

  def map(app, event : SF::Event::MouseMoved)
    super

    app.pan(@origin - app.coords(event))

    self
  end
end

class Console
  include SF::Drawable

  # TODO: make console NOT a singleton. Currently it's very
  # hard to access console otherwise from ResponseContext,
  # make that easier e.g. via a Stream?
  INSTANCE = new(rows: 24, cols: 80)

  @col : Float32

  def initialize(@rows : Int32, @cols : Int32)
    @scrolly = 0
    @folded = false
    @folded_manually = false

    @buffer = [] of String

    @text = SF::Text.new("", FONT, 11)
    @text.fill_color = SF::Color::White

    @col = FONT.get_glyph(' '.ord, @text.character_size, false).advance
    @row = @text.character_size * @text.line_spacing

    @bg = SF::RectangleShape.new
    @bg.size = SF.vector2f(@col * @cols + 4, @row * @rows + 4)
    @bg.fill_color = SF::Color.new(0x11, 0x11, 0x11)

    # Create a rectangle for the header
    @header = SF::RectangleShape.new
    @header.size = @bg.size + SF.vector2f(2, header_height + 1)
    @header.fill_color = SF::Color.new(0x54, 0x80, 0x95)

    # Create title text
    @title = SF::Text.new(title_string, FONT_BOLD, 11)

    l, c, h = LCH.rgb2lch(0x54, 0x80, 0x95)

    # @title.fill_color = p SF::Color.new(*LCH.lch2rgb(30, c, h))
    @title.fill_color = SF::Color.new(28, 76, 95)
  end

  def title_string
    String.build do |io|
      io << "** Console ** Double click to fold/unfold"
      unless @buffer.empty?
        scroll_win_start = Math.max(0, @buffer.size - @rows - @scrolly)
        scroll_win_end = scroll_win_start + @rows
        io << " (from " << scroll_win_start << " to " << scroll_win_end << ")"
      end
    end
  end

  def header_height
    @row + 3
  end

  def includes?(other : Vector2)
    @header.global_bounds.contains?(other.sf)
  end

  def move(v2)
    @header.position += v2
  end

  def move(x, y)
    move(SF.vector2f(x, y))
  end

  getter? elevated = false
  @pressed_at = SF.vector2f(0, 0)

  def handle(event : SF::Event::MouseWheelScrolled)
    @scrolly = (@scrolly + event.delta.to_i).clamp(0..Math.max(0, @buffer.size - @rows))
  end

  def handle(event : SF::Event::MouseButtonPressed, clicks : Int32)
    mpos = App.the.coords(event).sf
    if clicks == 2
      self.folded = !@folded
      @folded_manually = true
    else
      @elevated = true
      @pressed_at = mpos
    end
  end

  def handle(event : SF::Event::MouseButtonReleased)
    @elevated = false
  end

  def handle(event : SF::Event::MouseMoved)
    return unless @elevated
    mpos = App.the.coords(event).sf

    move(mpos - @pressed_at)

    @pressed_at = mpos
  end

  def handle(event)
  end

  SCROLLBACK = 1024

  def print(string : String)
    unless @folded_manually
      self.folded = false
    end

    lines = [] of String

    string.split('\n') do |line|
      if line.size > @cols
        lines << line[...@cols]
        lines << line[@cols..]
      else
        lines << line
      end
    end

    if @buffer.size + lines.size > SCROLLBACK
      @buffer.shift(lines.size)
    end

    @buffer.concat(lines)
  end

  def folded=(@folded)
    if folded
      @header.size = SF.vector2f(@header.size.x, header_height)
    else
      @header.size = @bg.size + SF.vector2f(2, header_height + 1)
    end
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    @header.draw(target, states)

    @title.string = title_string

    title_width = @title.global_bounds.width + @title.local_bounds.left
    title_height = @title.global_bounds.height + @title.local_bounds.top

    @title.position = Vector2.new(
      @header.position + SF.vector2f((@header.size.x - title_width)/2, (header_height - title_height)/2)
    ).sfi

    @title.draw(target, states)

    return if @folded

    # Shift bg and text header to go "inside" header
    @bg.position = @header.position + SF.vector2f(1, header_height)
    start = Math.max(0, @buffer.size - @rows - @scrolly)
    visible = @buffer[start, Math.min(@rows, @buffer.size - start)]
    @bg.draw(target, states)

    visible.each_with_index do |line, index|
      @text.string = line
      @text.position = SF.vector2f(@bg.position.x + 2, @bg.position.y + @row * index + 2)
      @text.draw(target, states)
    end
  end

  def draw(app : App, target : SF::RenderTarget)
    target.draw(self)
  end
end

class App
  include SF::Drawable

  class_getter the = App.new
  class_getter time = ClockAuthority.new

  getter tank : Tank
  getter console : Console

  @mode : Mode

  private def mode=(other : Mode)
    return if @mode.same?(other)

    other.unload(self)
    @mode = other
    @mode.load(self)
  end

  def initialize
    @editor = SF::RenderTexture.new(1280, 720, settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @editor.smooth = false
    @hud = SF::RenderTexture.new(1280, 720, settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @hud.smooth = false

    @editor_window = SF::RenderWindow.new(SF::VideoMode.new(1280, 720), title: "Synapse — Editor",
      settings: SF::ContextSettings.new(depth: 24, antialiasing: 8)
    )
    @editor_window.framerate_limit = 60
    @editor_size = @editor_window.size

    @scene_window = SF::RenderWindow.new(SF::VideoMode.new(640, 480), title: "Synapse — Scene",
      settings: SF::ContextSettings.new(depth: 24, antialiasing: 8)
    )

    @scene_window.framerate_limit = 60

    @tank = Tank.new
    @tt = TimeTable.new(App.time)

    @console = Console::INSTANCE
    @console.folded = true
    @console.move(40, 20)

    @tt.every(10.seconds) { GC.collect }

    # FIXME: for some reason both of these create()s leak a
    # huge lot of memory when editor window is resized.
    #
    # Doing this "resize check" every 2 seconds rather than
    # on every resize amortizes this a little bit, but just a
    # little bit: there is still a huge memory leak if you
    # resize the window "too much".
    @tt.every(2.seconds) do
      unless @editor_window.size == @editor_size
        @editor_size = @editor_window.size

        @editor.create(@editor_size.x, @editor_size.y,
          settings: SF::ContextSettings.new(depth: 24, antialiasing: 8)
        )

        @hud.create(@editor_size.x, @editor_size.y,
          settings: SF::ContextSettings.new(depth: 24, antialiasing: 8)
        )
      end
    end

    @tank.vein(to: 0.at(0))
    @tank.insert(Actor.new)

    @mode = Mode::Normal.new
    @mode.load(self)
  end

  def default_cursor
    SF::Cursor.from_system(SF::Cursor::Type::Arrow)
  end

  def editor_cursor=(other : SF::Cursor)
    @editor_window.mouse_cursor = other
  end

  def coords(event)
    coords = @editor.map_pixel_to_coords SF.vector2f(event.x, event.y)
    coords.x.at(coords.y)
  end

  def prn(chars : String)
    @scene_window_buffer.string += chars
  end

  def pan(delta : Vector2)
    view = @editor.view
    view.center += delta.sf
    view.center = SF.vector2f(view.center.x.round, view.center.y.round)
    @editor.view = view
  end

  def follow
    @editor.view = @tank.follow(@editor.view)
  end

  @factor = 1.0

  def zoom(factor : Number)
    return unless 0.1 <= @factor * factor <= 3

    @factor *= factor

    view = @editor.view
    view.center = SF.vector2f(view.center.x.round, view.center.y.round)
    view.zoom(factor)
    @editor.view = view
  end

  def unzoom
    @factor = 1.0
    view = SF::View.new
    view.center = SF.vector2f(@editor.view.center.x.round, @editor.view.center.y.round)
    view.size = SF.vector2f(@editor.size.x, @editor.size.y)
    @editor.view = view
  end

  @time = true

  def stop_time
    return unless @time

    @time = false
  end

  def start_time
    return if @time

    @time = true

    App.time.unpause
  end

  def toggle_time
    @time = !@time
    if @time
      App.time.unpause
    end
  end

  def draw(target, states)
    #
    # Draw tank.
    #
    @editor.clear(SF::Color.new(0x21, 0x21, 0x21, 0xff))
    @tank.draw(:entities, @editor)
    @tank.draw(:actors, @scene_window)
    # Draw console window...
    @console.draw(self, @editor)
    @editor.display

    #
    # Draw hud (mode).
    #
    @hud.clear(SF::Color.new(0x21, 0x21, 0x21, 0))

    # Draw whatever mode wants to draw...
    @mode.draw(self, @hud)

    # Optionally draw "time is paused" window
    unless @time
      text = SF::Text.new("Time is paused...", FONT_UI_MEDIUM, 14)
      text.fill_color = SF::Color.new(0x99, 0x99, 0x99)
      text_size = SF.vector2f(
        text.global_bounds.width + text.local_bounds.left,
        text.global_bounds.height + text.local_bounds.top,
      )

      padding = SF.vector2f(10, 5)

      bg_rect = SF::RectangleShape.new
      bg_rect.fill_color = SF::Color.new(0x33, 0x33, 0x33)
      bg_rect.size = text_size + padding*2
      bg_rect.outline_thickness = 1
      bg_rect.outline_color = SF::Color.new(0x55, 0x55, 0x55)

      rect_x = target.view.center.x - bg_rect.size.x/2
      rect_y = target.size.y - bg_rect.size.y * 2
      bg_rect.position = SF.vector2f(rect_x, rect_y)

      text.position = Vector2.new(bg_rect.position + padding).sfi

      @hud.draw(bg_rect)
      @hud.draw(text)
    end

    @hud.display

    #
    # Draw sprites for both.
    #
    target.draw SF::Sprite.new(@editor.texture)
    target.draw SF::Sprite.new(@hud.texture), SF::RenderStates.new(SF::BlendMode.new(SF::BlendMode::SrcAlpha, SF::BlendMode::OneMinusSrcAlpha))
  end

  def run
    while @editor_window.open?
      while event = @editor_window.poll_event
        case event
        when SF::Event::Closed
          @editor_window.close
          @scene_window.close
        when SF::Event::Resized
          view = @editor.view
          view.size = SF.vector2f(event.width, event.height)
          view.center = SF.vector2f(view.center.x.round, view.center.y.round)
          view.zoom(@factor)
          @editor.view = view

          view = @hud.view
          view.size = SF.vector2f(event.width, event.height)
          @hud.view = view

          win_view = @editor_window.view
          win_view.size = SF.vector2f(event.width, event.height)
          win_view.center = win_view.size/2
          @editor_window.view = win_view
        else
          self.mode = @mode.map(self, event)
        end
      end

      while event = @scene_window.poll_event
        case event
        when SF::Event::Closed
          @scene_window.close
          @editor_window.close
        when SF::Event::KeyPressed
          @tank.each_vein &.emit("key", [event.code.to_s] of Memorable, color: Cell.color(l: 80, c: 70))
        when SF::Event::TextEntered
          chr = event.unicode.chr
          if chr.printable?
            @tank.each_vein &.emit("chr", [chr.to_s] of Memorable, color: Cell.color(l: 80, c: 70))
          end
        end
      end

      @tt.tick

      @tank.tick(1/60) if @time
      @mode.tick(self)

      @editor_window.clear(SF::Color.new(0x21, 0x21, 0x21))
      @scene_window.clear(SF::Color::White)

      @editor_window.draw(self)

      @scene_window.display
      @editor_window.display
    end
  end
end

# [x] double click to add cell
# [x] click on empty = uninspect
# [x] click on existing = inspect
# [x] another window -- scene
# [x] vein -- emits events (msg), receives commands (msg). a rectangle
# [x] vein should emit small distance, weak & fixed time, messages
# [X] Wire -- connect to cell, transmit message, emit at the end
# [x] rewrite parser using line-oriented approach, keep offsets correct
#     add support for comments using '--', add support for Lua header, e.g.
#         -- This is implicitly stored under the "initialize" rule,
#         -- which is automatically rerun on change.
#         i = 0
#         j = 0
#
#         mouse |
#           print(i, j, i / j)
#
#         heartbeat |
#           self.i = self.i + 1
#
#         heartbeat 300ms |
#           self.j = self.j + 1
#
# [x] make message header underline more dimmer (redesign message header highlight)
# [x] autocenter view on cell when in inspect mode
# [x] scroll left/right/up/down when inspected protocoleditor cursor is out of view
# [x] halo relative cells when any cell is inspected
# [x] draw wires under cells
# [x] change color of wires to match cell color (exactly the same as halo!)
# [x] support cell removal
# [x] underline message headers in protocoleditor
# [x] Wheel for Yscroll in Normal mode, Shift-Wheel for X scroll
# [x] add timed heartbeat overload syntax, e.g `heartbeat 300ms | ...`, `heartbeat 10ms | ...`,
#     while simply `heartbeat |` will run on every frame
# [x] fix bug: when a single cell±editor doesnt fit into screen (eg zoom) screen tearing occurs!!
# [x] toggle time with spacebar
# [x] when typing alphanumeric with nothing inspected, create a cell
# [x] implement ctrl-c/ctrl-v of buffer contents
# [x] In Mode#draw(), draw hint panel which says what mode it is and how to
#     use it; draw into a separate RenderTexture for no zoom on it
# [x] do not show hint panel when editor is active (aka when anything is being inspected)
# [x] add a console window to hud inside editor and redirect print() to that console
# [x] print "paused" on hud when time is stopped
# [x] display buffer size in console title
# [x] add '*' wildcard message
# [x] introduce clock authority which will control clocks for heartbeats &
#     timetables, and make the clocks react to toggle time
# [x] stop_time on inspect
# [x] draw console in tank
# [x] expose keyword in messageresponsecontext
# [ ] support clone using C-Middrag
# [ ] wormhole wire -- listen at both ends, teleport to the opposite end
#     represented by two circles "regions" at both ends connected by a 1px line
# [ ] add "sink" messages which store the last received message
#     and answer after N millis
# [ ] -refactor- WIPE OUT event+mode system. use something simple eg event
#     streams; have better focus (mouse follows focus but some things e.g.
#     editor can seize it)
# [ ] add selection rectangle (c-shift mode) to drag/copy/clone/delete multiple entities
#     selection rectangle :: to select new things
#     selection :: contains new and previously selected things
# [ ] add message reflection (get/set name, get/set parameters, get/set sink, get/set code etc)
# [ ] make it possible for cells to send each other definitions
# [ ] make it possible for cells to send each other pieces of code
# [ ] extend the notion of *actors*: allow cells to own actors in Scene
#     and move/resize/fill/control them.
# [ ] add drawableallocator object pool to reuse shapes instead of reallocating
#     them on every frame in draw(...); attach DA to App, pass to draw()s
#     inside DA.frame { ... } in mainloop
# [ ] make message name italic (aka basic syntax highlighting)
# [ ] animate what's in brackets `heartbeat [300ms] |` based on progress of
#     the associated task (very tiny bit of dimmer/lighter; do not steal attention!)
# [ ] use Tank#time (ish) instead of App.time for pausing time in a specific
#     tank rather than the whole app
# [ ] refactor, simplify, remove useless method dancing? use smaller
#     objects, object-ize everything, get rid of getters and properties
#     in Cell, e.g. refactor all methods that use (*, in tank : Tank) to a
#     separate object e.g. CellView
# [ ] implement save/load for the small objects & the system overall: save/load image feature
# [ ] split into different files, use Crystal structure
# [ ] optimize?
# [ ] write a few examples, record using GIF
# [ ] write README with gifs
# [ ] upload to GH

App.the.run
