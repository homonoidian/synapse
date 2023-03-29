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

FONT = SF::Font.from_memory({{read_file("../../.local/share/fonts/cozette.bdf")}}.to_slice)

# https://www.desmos.com/calculator/6rnk1vp9su
def fmessage_amount(strength : Float)
  if strength <= 80
    1.8256 * Math.log(strength)
  elsif strength <= 150
    6/1225 * (strength - 80)**2 + 8
  else
    8 * Math.log(strength - 95.402)
  end
end

def fmessage_lifespan_ms(strength : Float)
  if strength <= 155
    2000 * Math::E**(-strength/60)
  else
    150
  end
end

module Inspectable
end

record Message, id : UUID, sender : UUID, keyword : String, args : Array(Memorable), strength : Float64, decay = 0.0

abstract class Entity
  include SF::Drawable

  getter id : UUID
  getter tt = TimeTable.new

  @decay_task_id : UUID

  def initialize(@color : SF::Color, lifespan : Time::Span?)
    @id = UUID.random
    @tanks = [] of Tank

    return unless lifespan

    @decay_task_id = tt.after(lifespan) do
      @tanks.each { |tank| suicide(in: tank) }
    end
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
record ErrResult < EvalResult, error : Lua::LuaError | ArgumentError, signature : {String, Int32}, rule : Rule, offset : Int32

class ResponseContext
  def initialize(@rule : Rule, @receiver : Cell, @message : Message, @attack = 0.0)
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

  # Populates *stack* with globals related to this response context.
  def fill(stack : Lua::Stack)
    stack.set_global("id", @receiver.id.to_s)

    stack.set_global("sender", @message.sender.to_s)
    stack.set_global("impact", @message.strength)
    stack.set_global("decay", @message.decay)

    stack.set_global("attack", Math.degrees(@attack))
    stack.set_global("evasion", Math.degrees(Math.opposite(@attack)))

    stack.set_global("heading", ->heading(LibLua::State))

    stack.set_global("strength", ->strength(LibLua::State))
    stack.set_global("send", ->send(LibLua::State))
    stack.set_global("swim", ->swim(LibLua::State))
  end
end

class Rule
  class RuleMirror
    include LuaCallable

    def initialize(@rule : Rule)
    end

    def keyword
      @rule.@keyword
    end

    def params
      @rule.@params
    end

    def code
      @rule.@lua
    end
  end

  def initialize(@keyword : String, @params : Array(String), @lua : String, @offset : Int32)
    @mirror = RuleMirror.new(self)
  end

  def unify(other : Rule)
    return self if self == other
    return other unless @keyword == other.@keyword

    @params = other.@params
    @lua = other.@lua
    @offset = other.@offset

    self
  end

  def unify(store)
    prev = store[{@keyword, @params.size}]?

    store[{@keyword, @params.size}] = prev ? prev.unify(self) : self
  end

  def prn(receiver)
    ->(state : LibLua::State) {
      stack = Lua::Stack.new(state, :all)
      receiver.prn(stack.pop.to_s)
      return 1
    }
  end

  def result(receiver : Cell, message : Message, attack = 0.0) : EvalResult
    response = ResponseContext.new(self, receiver, message, attack)

    stack = Lua::Stack.new
    response.fill(stack)

    # stack.set_global("prn", prn(receiver))

    # # receiver() -- return my id
    # # sender() -- return sender id
    # # swim() -- set velocity
    # # emit(keyword) -- emit without args
    # # send(keyword, args) -- emit with default strength

    # stack.set_global("swim", swim(receiver))
    # stack.set_global("self", response)
    # stack.set_global("mirror", @mirror)
    stack.set_global("self", receiver.memory)
    @params.zip(message.args) do |param, arg|
      stack.set_global(param, arg)
    end

    begin
      stack.run(@lua, @keyword)
      OkResult.new
    rescue e : Lua::LuaError
      ErrResult.new(e, {@keyword, @params.size}, self, @offset)
    rescue e : ArgumentError
      ErrResult.new(e, {@keyword, @params.size}, self, @offset)
    ensure
      stack.close
    end
  end

  def ans(receiver : Cell, vesicle : Vesicle, attack : Float64) : EvalResult
    result(receiver, vesicle.message, attack)
  end

  RUN_ALLOW = {"heartbeat"}

  def run(receiver : Cell, message : Message)
    raise "BUG: denied 'run!' to '#{@keyword}'" unless RUN_ALLOW.includes?(@keyword)

    result(receiver, message)
  end

  def_equals_and_hash @keyword, @params, @lua, @offset
end

class Protocol
  getter id : UUID

  def initialize
    @id = UUID.random
    @rules = {} of {String, Int32} => Rule
  end

  def clear
    @rules.clear
  end

  def unify(other : Rule)
    other.unify(@rules)
  end

  def fetch_rule?(keyword : String, nargs : Int32)
    @rules[{keyword, nargs}]?
  end

  def sync(signatures : Set({String, Int32}))
    # Delete those decls that are not in the keys array.
    @rules = @rules.reject { |key, _| !key.in?(signatures) }
  end

  def ans(receiver : Cell, vesicle : Vesicle) : EvalResult
    return OkResult.new unless rule = fetch_rule?(vesicle.keyword, vesicle.nargs)

    # Attack is a heading pointing hdg the vesicle.
    delta = (vesicle.mid - receiver.mid)
    attack = Math.atan2(-delta.y, delta.x)

    rule.ans(receiver, vesicle, attack)
  end

  # Fetches the heartbeat message declaration. Returns nil if
  # none is found.
  def heartbeat?
    fetch_rule?("heartbeat", nargs: 0)
  end
end

class ProtocolEditorModel
  getter id : UUID
  property store : Protocol
  property cursor : Int32
  property buffer : TextBuffer
  property markers : Hash(Int32, ProtocolEditor::Marker)
  property? sync : Bool

  def initialize(@store, @cursor = 0, @buffer = TextBuffer.new, @markers = {} of Int32 => ProtocolEditor::Marker, @sync = true)
    @id = UUID.random
  end
end

class ProtocolEditor
  include SF::Drawable

  record Marker, color : SF::Color, offset : Int32, tally : Hash(String, Int32) do
    def initialize(color, offset, message : String)
      hash = Hash(String, Int32).new(0)

      initialize(color, offset, message.lines.tally_by(hash, &.itself))
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

  getter model

  def initialize(@cell : Cell, @model : ProtocolEditorModel)
  end

  def initialize(cell : Cell, store : Protocol)
    initialize(cell, ProtocolEditorModel.new(store))
  end

  def initialize(cell : Cell, other : ProtocolEditor)
    initialize(cell, other.@model)
  end

  def mark(color : SF::Color, offset : Int32, message : String)
    mark Marker.new(color, offset, message)
  end

  def mark(marker : Marker)
    if prev = markers[marker.offset]?
      marker = prev.stack(marker)
    end

    markers[marker.offset] = marker
  end

  def source
    buffer.string
  end

  def update
    markers.clear
    buffer.update do |source|
      yield source
    end
    parse
  end

  private delegate :cursor, :cursor=, to: @model
  private delegate :buffer, :buffer=, to: @model
  private delegate :store, :store=, to: @model
  private delegate :markers, :markers=, to: @model
  private delegate :sync?, :sync=, to: @model

  def unsync(err : ErrResult)
    # Signal that what's currently running is out of sync from
    # what's being shown.
    self.sync = false
    mark(SF::Color::Red, err.offset, err.error.message || "lua error")
  end

  def handle(event : SF::Event::KeyPressed)
    case event.code
    when .backspace?
      return if cursor.zero?

      e = cursor - 1
      b = e
      if event.control
        b = buffer.word_begin_at(b)
      end

      update do |source|
        source.delete_at(b..e)
      end

      self.cursor -= e - b + 1
    when .delete?
      return if cursor == buffer.size - 1

      b = cursor
      e = b
      if event.control
        e = buffer.word_end_at(e)
      end

      update do |source|
        source.delete_at(b..e)
      end
    when .enter?
      line = buffer.line_at(cursor)

      head = String.build do |io|
        io << '\n'

        next if cursor == line.b
        buffer.line_at(cursor).each_char do |char|
          break unless char.in?(' ', '\t')
          io << char
        end
      end

      update do |source|
        source.insert(cursor, head)
      end

      self.cursor += head.size
    when .tab?
      update do |source|
        source.insert(cursor, "  ")
      end
      self.cursor += 2
    when .left?
      return if cursor.zero?

      self.cursor = event.control ? buffer.word_begin_at(cursor - 1) : cursor - 1
    when .right?
      return if cursor == buffer.size - 1

      self.cursor = event.control ? buffer.word_end_at(cursor + 1) : cursor + 1
    when .home?
      line = buffer.line_at(cursor)
      self.cursor = line.b
    when .end?
      line = buffer.line_at(cursor)
      self.cursor = line.e
    when .up?
      line = buffer.line_at(cursor)
      if line.first_line?
        self.cursor = 0
      else
        dest = buffer.fetch_line(line.ord - 1)
        self.cursor = dest.b + Math.min(cursor - line.b, dest.size)
      end
    when .down?
      line = buffer.line_at(cursor)
      if line.last_line?
        self.cursor = buffer.size - 1
      else
        dest = buffer.fetch_line(line.ord + 1)
        self.cursor = dest.b + Math.min(cursor - line.b, dest.size)
      end
    end
  end

  def handle(event : SF::Event::TextEntered)
    chr = event.unicode.chr

    return unless chr.printable?

    update do |source|
      source.insert(cursor, chr)
    end
    self.cursor += 1
  end

  def handle(event)
  end

  def parse
    error = nil
    source = self.source.strip

    signatures = Set({String, Int32}).new

    hint_color = SF::Color.new(0xFF, 0xCA, 0x28)

    if source.empty?
      self.sync = true
      store.sync(signatures)
      return
    end

    # Here's the syntax we're (roughly) aiming for.
    #
    #   <top> ::= <Rule>*
    #   <Rule> ::= <messageName> (WS <messageParam>)* WS "|" <messageBody>
    #   <messageBody> ::= <indent> [lua code] <dedent>
    #   <messageName> ::= [A-Za-z]\w*
    #   <messageParam> ::= [A-Za-z]\w*
    s = StringScanner.new(source)

    until s.eos?
      offset = s.offset

      unless name = s.scan(/(?:[A-Za-z]\w*)/)
        error = ProtocolEditor::Marker.new(hint_color, s.offset, "I want message name here!")
        break
      end

      params = [] of String
      while param = s.scan(/\s+(?:[A-Za-z]\w*)/)
        params << param.strip
      end

      unless s.scan(/\s+\|/)
        error = ProtocolEditor::Marker.new(hint_color, s.offset, "I want space followed by pipe '|' here!")
        break
      end

      lua = ""

      unless s.check(/\r?\n\s+|$/)
        error = ProtocolEditor::Marker.new(hint_color, s.offset, "I want this line to end! You should indent here, and then type some Lua.")
        break
      end

      # Rest is presumably a bunch of Lua lines like so:
      #
      #   <NL> <INDENT SPACES> line of lua ...
      #   <NL> <INDENT SPACES> line of lua ...
      #   ...
      #
      # While lines have even one leading whitespace, we should
      # consider them part of the Lua code. Therefore, let's
      # scan until there is a line *without* leading whitespace.
      lua = s.scan_until(/\r?\n(?=[^ \t])|$/) || lua

      signatures << {name, params.size}

      # Now we have all it takes to create a message rule.
      # Create it and unify with the existing decls.
      store.unify Rule.new(name, params, lua, offset)
    end

    unless error
      self.sync = true
      store.sync(signatures)
      return
    end

    mark(error)

    self.sync = false
  end

  def draw(target, states)
    origin = @cell.mid + @cell.class.radius * 1.1

    texture = FONT.get_texture(13)
    texture.smooth = false

    text = SF::Text.new(buffer.string, FONT, 13)
    text.line_spacing = 1.3

    text_width = text.global_bounds.width + text.local_bounds.left
    text_height = text.global_bounds.height + text.local_bounds.top

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
    bg_rect.outline_color = SF::Color.new(0x42, 0x42, 0x42, 0xee)
    bg_rect.size = SF.vector2f(text_width + 30, text_height + 30 - 2)
    bg_rect.draw(target, states)

    #
    # Draw thick left bar which shows whether the code is
    # synchronized with what's running.
    #
    bar = SF::RectangleShape.new
    bar.fill_color = sync_color
    bar.position = origin.sfi
    bar.size = SF.vector2f(4, text_height + 30)
    bar.draw(target, states)

    text.position = (origin + 15.at(15)).sfi

    #
    # Draw beam.
    #
    beam = SF::RectangleShape.new
    beam.fill_color = SF::Color.new(0xAE, 0xD5, 0x81)

    # If there is no source, beam is 1 pixel wide.
    cur = text.find_character_pos(cursor)
    nxt = text.find_character_pos(cursor + 1)

    beam.position = cur + SF.vector2f(1, 0)
    beam.size = SF.vector2f(Math.max(6, nxt.x - cur.x), text.character_size * text.line_spacing)
    beam.draw(target, states)

    #
    # Draw buffer contents.
    #
    text.fill_color = SF::Color.new(0xF5, 0xF5, 0xF5)
    text.draw(target, states)

    #
    # Draw markers
    #
    markers.each_value do |marker|
      coords = text.find_character_pos(marker.offset)

      # If cursor is in the line below marker offset, we actually
      # want this marker to be above.
      m_line = buffer.line_at(marker.offset)
      c_line = buffer.line_at(cursor)
      flip = c_line.ord == m_line.ord + 1

      offset = SF.vector2f(0, text.character_size * text.line_spacing)
      coords += flip ? SF.vector2f(3, 0) : offset

      # To enable variation while maintaining uniformity with
      # the original color.
      l, c, h = LCH.rgb2lch(marker.color.r, marker.color.g, marker.color.b)

      bg_l = 70
      fg_l = 40

      mtext = SF::Text.new(marker.message, FONT, 13)

      mbg_rect_position = coords + (flip ? SF.vector2f(-6, -(text.character_size * text.line_spacing) - 0.6) : SF.vector2f(-3, 4.5))
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
      mtext.position = mbg_rect.position + SF.vector2f(5, 2)
      mtext.draw(target, states)
    end
  end
end

alias Memorable = Bool | Float64 | Lua::Table | String | Nil

class Cell < RoundEntity
  include Inspectable

  class InstanceMemory
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

  getter memory = InstanceMemory.new

  @wires = Set(Wire).new

  def initialize
    super(self.class.color, lifespan: nil)

    @store = Protocol.new

    @editor = uninitialized ProtocolEditor
    @editor = ProtocolEditor.new(self, @store)
  end

  def initialize(color : SF::Color, @store : Protocol, editor : ProtocolEditor)
    super(color, lifespan: nil)

    @editor = uninitialized ProtocolEditor
    @editor = ProtocolEditor.new(self, editor)
  end

  def copy
    Cell.new(@color, @store, @editor)
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

  @handled = Set(UUID).new

  def receive(vesicle : Vesicle, in tank : Tank)
    return if vesicle.message.id.in?(@handled)

    @handled << vesicle.message.id

    result = @store.ans(receiver: self, vesicle: vesicle)

    return unless result.is_a?(ErrResult)

    fail(result, tank)
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
    true
  end

  def stop_inspection?(in tank : Tank)
    true
  end

  @corrupt_heartbeat_hash : UInt64? = nil
  @corrupt_memory_hash : UInt64? = nil

  def heartbeat(in tank : Tank)
    return unless hb = @store.heartbeat?

    # If heartbeat message was decided corrupt, was not modified,
    # and instance memory is the same, then the corrupt heartbeat
    # message shall not be run.
    return if hb.hash == @corrupt_heartbeat_hash && @memory.hash == @corrupt_memory_hash

    result = hb.run(receiver: self, message: Message.new(UUID.random, @id, "heartbeat", [] of Memorable, 0))
    if result.is_a?(ErrResult)
      @corrupt_heartbeat_hash = result.rule.hash
      @corrupt_memory_hash = @memory.hash
      fail(result, in: tank)
      return
    else
      @corrupt_heartbeat_hash = nil
      @corrupt_memory_hash = nil
    end
  end

  def tick(delta : Float, in tank : Tank)
    super
    heartbeat(in: tank)
  end

  def draw(tank : Tank, target)
    super

    return unless tank.inspecting?(self)

    target.draw(@editor)
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
    super(self.class.color, lifespan: nil)

    @drawable = SF::VertexArray.new(SF::Lines)
    @drawable.append(SF::Vertex.new(@src.mid.sf, @color))
    @drawable.append(SF::Vertex.new(@dst.sf, @color))
  end

  def self.color
    SF::Color.new(0x5C, 0x6B, 0xC0)
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
    @text = SF::Text.new("", FONT, 13)
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

    @tt = TimeTable.new

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

    other
  end

  def prn(cell : Cell, message : String)
    @actors.each do |actor|
      actor.prn(message)
    end
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
    @space.remove(object) if @space.contains?(object)
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

    return unless vamt.in?(1..1024) # safety belt

    vrays = Math.max(1, vamt // 2)

    vamt = vamt.to_i
    vrays = vrays.to_i
    vlifespan = fmessage_lifespan_ms(message.strength).milliseconds

    vamt.times do |v|
      angle = Math.radians(((v / vrays) * 360) + rand * 360)
      impulse = angle.dir * (message.strength * rand)
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
  end

  def handle(event : SF::Event)
    @inspecting.try &.handle(event)
  end

  include SF::Drawable

  def draw(target, states)
    # dd = SFMLDebugDraw.new(target, states)
    # dd.draw(@space)
  end

  def draw(what : Symbol, target : SF::RenderTarget)
    case what
    when :entities
      # Draw all entities except the inspected one (if any).
      each_entity do |entity|
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

  # Maps *event* to the next mode.
  def map(app, event)
    app.tank.handle(event)

    self
  end

  def draw(target, states)
  end
end

MOUSE_ID = UUID.random

class Mode::Normal < Mode
  def initialize(@elevated : Cell? = nil, @ondrop : Mode = self)
  end

  @clicks = 0
  @clickclock = SF::Clock.new

  def map(app, event : SF::Event::MouseButtonPressed)
    coords = app.coords(event)

    if @clickclock.elapsed_time.as_milliseconds < 300
      @clicks = 2
    else
      @clicks = 1
    end

    @clickclock.restart

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
        return self
      end
      @elevated = cell
      app.tank.inspect(cell)
    when .right?
      app.tank.distribute(coords, Message.new(
        id: UUID.random,
        sender: MOUSE_ID,
        keyword: "mouse",
        args: [] of Memorable,
        strength: 140
      ), SF::Color::White, deadzone: 1)
    end

    self
  end

  def map(app, event : SF::Event::MouseButtonReleased)
    @elevated.try &.stop
    @elevated = nil

    @ondrop
  end

  def map(app, event : SF::Event::MouseMoved)
    @elevated.try do |cell|
      cell.mid = app.coords(event)
    end

    self
  end

  def map(app, event : SF::Event::KeyPressed)
    case event.code
    when .l_control?, .r_control?
      return Mode::AwaitingPan.new
    when .l_shift?, .r_shift?
      return Mode::Wiring.new(WireConfig.new)
    when .escape?
      app.tank.inspect(nil)
    end
    super
  end
end

record WireConfig, from : Cell? = nil, to : Vector2? = nil

class Mode::Wiring < Mode::Normal
  @mouse : Vector2

  def initialize(@wire : WireConfig)
    super()

    @mouse = 0.at(0)
  end

  def submit(app : App, src : Cell, dst : Vector2)
    app.tank.wire(from: src, to: dst)
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

  def map(app, event : SF::Event::MouseMoved)
    @mouse = app.coords(event)

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

  def draw(target, states)
    return unless @wire.from || @wire.to

    src = @wire.from.try &.mid || @mouse
    dst = @wire.to || @mouse

    va = SF::VertexArray.new(SF::Lines)
    va.append(SF::Vertex.new(src.sf, Wire.color))
    va.append(SF::Vertex.new(dst.sf, Wire.color))

    va.draw(target, states)
  end
end

class Mode::AwaitingPan < Mode
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

class Mode::Panning < Mode::AwaitingPan
  def initialize(@origin : Vector2)
  end

  def map(app, event : SF::Event::MouseButtonReleased)
    return super unless event.button.left?

    Mode::AwaitingPan.new
  end

  def map(app, event : SF::Event::MouseMoved)
    app.pan(@origin - app.coords(event))

    self
  end
end

class App
  getter tank : Tank

  def initialize
    @editor = SF::RenderWindow.new(SF::VideoMode.new(1280, 720), title: "Synapse — Editor",
      settings: SF::ContextSettings.new(depth: 24, antialiasing: 8)
    )
    @editor.framerate_limit = 60
    @scene = SF::RenderWindow.new(SF::VideoMode.new(640, 480), title: "Synapse — Scene",
      settings: SF::ContextSettings.new(depth: 24, antialiasing: 8)
    )

    @scene.framerate_limit = 60

    @tank = Tank.new
    @tt = TimeTable.new
    @tt.every(10.seconds) { GC.collect }

    @tank.vein(to: 0.at(0))
    @tank.insert(Actor.new)
  end

  def coords(event)
    coords = @editor.map_pixel_to_coords SF.vector2f(event.x, event.y)
    coords.x.at(coords.y)
  end

  def prn(chars : String)
    @scene_buffer.string += chars
  end

  def pan(delta : Vector2)
    view = @editor.view
    view.center += delta.sf
    @editor.view = view
  end

  @factor = 1.0

  def zoom(factor : Number)
    return unless 0.1 <= @factor * factor <= 3

    @factor *= factor

    view = @editor.view
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

  @mode : Mode = Mode::Normal.new

  def run
    while @editor.open?
      while event = @editor.poll_event
        case event
        when SF::Event::Closed
          @editor.close
          @scene.close
        when SF::Event::Resized
          view = @editor.view
          view.size = SF.vector2f(event.width, event.height)
          view.center = SF.vector2f(@editor.view.center.x.round, @editor.view.center.y.round)
          view.zoom(@factor)
          @editor.view = view
        else
          @mode = @mode.map(self, event)
        end
      end

      while event = @scene.poll_event
        case event
        when SF::Event::Closed
          @scene.close
          @editor.close
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
      @tank.tick(1/60)

      @editor.clear(SF::Color.new(0x21, 0x21, 0x21))
      @scene.clear(SF::Color::White)
      @tank.draw(:entities, @editor)
      @tank.draw(:actors, @scene)
      @editor.draw(@mode)

      @scene.display
      @editor.display
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
# [ ] rewrite parser using line-oriented approach, keep offsets correct
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
# [ ] add timed heartbeat overload syntax, e.g `heartbeat 300ms | ...`, `heartbeat 10ms | ...`,
#     while simply `heartbeat |` will run on every frame
# # [ ] wormhole wire -- listen at both ends, teleport to the opposite end
#       represented by two circles at both ends connected by a 1px line
# [ ] scroll left/right/up/down when inspected protocoleditor cursor is out of view
# [ ] underline message headers in protocoleditor

app = App.new
app.run
