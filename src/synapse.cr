# FUN FACT: cells can move using messages
# FUN FACT: attacking one's own messages will make the cell follow entropy mountains,
#           evading one's own messages will make the cell follow entropy valleys
# NOT SO FUN FACT: reading Tank#entropy() takes 30% of time in tick(). entropy is the
#                  biggest performance crappoint because it's read for every vesicle.
#                  when chemistries are there perhaps it'd be best to remove entropy()
#                  for vesicles (at least do jitter(0.0) by default for them)
# ANOTHER NOT SO FUN FACT: drawing vesicles is the second most expensive operation.
#                  perhaps drawing them as simple pixels will help, and also reduce
#                  the amount of vesicles drawn based on zoom level. another idea is
#                  to add a "toggle draw vesicles" function

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
require "open-simplex-noise"

module CellEditorEntity # FIXME: ???
  delegate :position, :position=, to: @view

  def size
    @view.size
  end

  def move(position : SF::Vector2)
    @view.position = position.round

    refresh
  end

  def lift
  end

  def drop
  end
end

require "./synapse/ext"

require "./synapse/util/*"
require "./synapse/system/entity"
require "./synapse/system/physical_entity"
require "./synapse/system/morph_entity"
require "./synapse/system/*"
require "./synapse/ui/view"
require "./synapse/ui/dimension"
require "./synapse/ui/controller"

require "./synapse/ui/buffer_editor"
require "./synapse/ui/buffer_editor_row"
require "./synapse/ui/buffer_editor_column"

require "./synapse/ui/draggable"
require "./synapse/ui/rule_editor"
require "./synapse/ui/icon_view"

require "./synapse/ui/input_field"
require "./synapse/ui/input_field_row"
require "./synapse/ui/rule_header"
require "./synapse/ui/keyword_rule_header"
require "./synapse/ui/keyword_rule_editor"

require "./synapse/ui/*"

require "./ped2"

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

def fmagn_to_flow_scale(magn : Float)
  if 3.684 <= magn
    50/magn
  elsif magn > 0
    magn**2
  else
    0
  end
end

def fmessage_strength_to_jitter(strength : Float)
  if strength.in?(0.0..1000.0)
    1 - (1/1000 * strength**2)/1000
  else
    0.0
  end
end

record Message, keyword : String, args : Array(Memorable)

class Vesicle < CircularEntity
  include Jitter
  include SF::Drawable

  # Returns the message transported by this vesicle.
  getter message : Message

  # Returns the strength with which this vesicle was emitted.
  getter strength : Float64

  def initialize(
    tank : Tank,
    @message : Message,
    angle_rad : Float,
    @strength : Float64,
    lifespan : Time::Span,
    color : SF::Color,
    @birth : Time::Span,
    randomize = true
  )
    super(tank, color, lifespan)

    impulse = angle_rad.dir * (randomize ? (10.0..100.0).sample : strength) # FIXME: should depend on strength

    @body.apply_impulse_at_local_point(impulse.cp, CP.v(0, 0))
  end

  def self.z_index
    1
  end

  def jangles
    {0, 90, 180, 270}
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

  def tick(delta : Float)
    @jitter = fmessage_strength_to_jitter(@strength * (1 - decay))

    super
  end

  def smack(other : CellAvatar)
    other.receive(self)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    vary = SF::VertexArray.new(SF::Points, 1)
    vary.append SF::Vertex.new(mid.sfi, @color)
    vary.draw(target, states)
  end
end

alias MemorableValue = Bool | Float64 | Lua::Table | String | Nil
alias Memorable = OwnedProtocol | PackedProtocol | MemorableValue

# Raised when a receiver cell wants to commit suicide.
class CommitSuicide < Exception
end

# An instance of a `Cell` inside a specific tank.
#
# Cells can "live" in multiple tanks simultaneously, that is, with their
# "brains" "floating in the sky". *Instances* (so-called cell avatars)
# then communicate back and forth with the "brains" to remember decisions,
# swim, and so on.
class CellAvatar < CircularEntity
  include SF::Drawable

  include Jitter
  include Inspectable

  property? sync = true

  @wires = Set(Wire).new

  def initialize(tank : Tank, @cell : Cell, color : SF::Color, @editor : CellEditor)
    super(tank, color, lifespan: nil)

    @drawable = SF::CircleShape.new
    @drawable.fill_color = @color
    @drawable.radius = self.class.radius
  end

  def initialize(tank : Tank, cell : Cell)
    initialize(tank, cell,
      color: self.class.color,
      editor: CellEditor.new,
    )
  end

  delegate :memory, :adhere, :each_owned_protocol_with_name, to: @cell

  def jangles
    {0, 45, 90, 135, 180, 225, 270, 315}
  end

  def point_in_editor?(point : Vector2)
    origin = (mid + 32.at(32))
    corner = origin + Vector2.new(@editor.size)
    origin.x <= point.x <= corner.x && origin.y <= point.y <= corner.y
  end

  def self.radius
    8
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

  def halo_color
    l, c, h = LCH.rgb2lch(@color.r, @color.g, @color.b)

    SF::Color.new(*LCH.lch2rgb(80, 50, h))
  end

  def mid=(other : Vector2)
    super
    @wires.each &.sync
  end

  enum IRole
    Main
    Relative
  end

  def inspection_role?(is role : IRole? = nil) : IRole?
    @cell.each_relative_avatar do |relative|
      next unless @tank.inspecting?(relative)

      relative_role = same?(relative) ? IRole::Main : IRole::Relative
      if role.nil? || relative_role == role
        return relative_role
      end
    end

    nil
  end

  def into(view : SF::View) : SF::View
    return view unless inspection_role? is: IRole::Main

    top_left = view.center - SF.vector2f(view.size.x/2, view.size.y/2)
    bot_right = top_left + view.size

    dx = 0
    dy = 0

    origin = @drawable.position - SF.vector2f(CellAvatar.radius, CellAvatar.radius)
    corner = editor_position + @editor.size + SF.vector2f(CellAvatar.radius, CellAvatar.radius)
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

  def swim(heading : Float64, speed : Float64)
    @body.velocity = (Math.radians(heading).dir * 1.at(-1) * speed).cp
  end

  def add_wire(wire : Wire)
    @wires << wire
  end

  def emit(keyword : String, strength : Float64, color : SF::Color)
    emit(keyword, [] of Memorable, strength, color)
  end

  def emit(keyword : String, args : Array(Memorable), strength : Float64, color : SF::Color)
    message = Message.new(
      keyword: keyword,
      args: args
    )

    @wires.each do |wire|
      wire.distribute(message, color, strength)
    end

    @tank.distribute(mid, message, color, strength)
  end

  def interpret(result : ExpressionResult)
    unless result.is_a?(ErrResult)
      self.sync = true
      return
    end

    fail(result)
  end

  def replicate(to coords = mid)
    replica = CellAvatar.new(@tank, @cell.copy, @color, CellEditor.new)
    replica.mid = coords
    replica.summon
    replica
  end

  def summon
    super

    @cell.born(avatar: self)

    nil
  end

  def suicide
    super

    @cell.died(avatar: self)

    nil
  end

  def receive(vesicle : Vesicle)
    @cell.receive(avatar: self, vesicle: vesicle)
  rescue CommitSuicide
    suicide
  end

  def fail(err : ErrResult)
    # On error, if nothing is being inspected, ask tank to
    # start inspecting myself.
    #
    # In any case, add a mark to where the Lua code of the
    # declaration starts.
    @tank.inspect(self) if @tank.inspecting?(nil)

    # Signal that what's currently running is out of sync from
    # what's being shown.
    self.sync = false

    puts "=== Avatar #{@id} OF Cell #{@cell.id} failed: ===".colorize.bold
    pp err # FIXME: Uhmmm maybe have a better way to signal error???
  end

  def handle(event)
    @editor.handle(event)
  end

  def editor_position
    (mid + 32.at(32)).sfi
  end

  def focus
    @editor = @cell.to_editor
  end

  def blur
    @cell.adhere(@editor.to_protocol_collection)

    # FIXME: hack: Rerun birth rules unconditionally. But this
    # should happen only if they changed!
    @cell.born(avatar: self)
  end

  # Prefer using `Tank` to calling this method yourself because
  # sync of systoles/dyastoles between relatives is unsupported.
  def systole
    @cell.systole(avatar: self)
  rescue CommitSuicide
    suicide
  end

  # :ditto:
  def dyastole
    @cell.dyastole(avatar: self)
  rescue CommitSuicide
    suicide
  end

  @__texture = SF::RenderTexture.new(600, 400)

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    @drawable.position = (mid - CellAvatar.radius).sf
    @drawable.draw(target, states)

    return unless role = inspection_role?

    #
    # Draw halo
    #
    halo = SF::CircleShape.new
    halo.radius = CellAvatar.radius * 1.15
    halo.position = (mid - halo.radius).sf
    halo.fill_color = SF::Color::Transparent
    halo.outline_color = SF::Color.new(halo_color.r, halo_color.g, halo_color.b, 0x88)
    halo.outline_thickness = 1.5
    target.draw(halo)

    if role.main?
      sync_color = sync? ? SF::Color.new(0x81, 0xD4, 0xFA, 0x88) : SF::Color.new(0xEF, 0x9A, 0x9A, 0x88)
      sync_color_opaque = SF::Color.new(sync_color.r, sync_color.g, sync_color.b)

      #
      # Draw little circles at start of line to really show
      # which cell is selected.
      #
      start_circle = SF::CircleShape.new(radius: 2)
      start_circle.fill_color = sync_color_opaque
      start_circle.position = (mid - 2).sfi
      target.draw(start_circle)

      #
      # Draw background rectangle.
      #
      bg_rect = SF::RectangleShape.new
      bg_rect.fill_color = sync_color
      bg_rect.position = editor_position - SF.vector2(3, 1)
      bg_rect.size = @editor.size + SF.vector2f(4, 2)
      target.draw(bg_rect)

      #
      # Draw a line from origin of background to the center of
      # the cell.
      #
      va = SF::VertexArray.new(SF::Lines, 2)
      va.append(SF::Vertex.new(mid.sfi, sync_color_opaque))
      va.append(SF::Vertex.new(bg_rect.position, sync_color_opaque))
      target.draw(va)

      @__texture.clear(SF::Color.new(0x25, 0x25, 0x25))
      @__texture.draw(@editor)
      @__texture.display

      sprite = SF::Sprite.new(@__texture.texture)
      sprite.position = editor_position

      target.draw(sprite)
    end
  end
end

class Vein < MorphEntity
  include SF::Drawable

  def initialize(tank : Tank)
    super(tank, SF::Color.new(0xE5, 0x73, 0x73, 0x33), lifespan: nil)

    @drawable = SF::RectangleShape.new
    @drawable.position = 0.at(0).sf
    @drawable.size = width.at(height).sf
    @drawable.fill_color = @color
  end

  def self.body : CP::Body
    CP::Body.new_static
  end

  def self.width
    10
  end

  def self.height
    720
  end

  def self.shape(body : CP::Body) : CP::Shape
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

  def width : Number
    self.class.width
  end

  def height : Number
    self.class.height
  end

  def emit(keyword : String, args : Array(Memorable), color : SF::Color)
    message = Message.new(
      keyword: keyword,
      args: args,
    )

    # Distribute at each 5th heightpoint.
    0.step(to: self.class.height, by: 10) do |yoffset|
      @tank.distribute_vein_bi(mid + yoffset.y, message, color, 400.milliseconds, strength: 50.0)
    end
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    @drawable.draw(target, states)
  end
end

class Wire < Entity
  include SF::Drawable

  def initialize(tank : Tank, @src : CellAvatar, @dst : Vector2)
    super(tank, @src.halo_color, lifespan: nil)

    @drawable = SF::VertexArray.new(SF::Lines)
    @drawable.append(SF::Vertex.new(@src.mid.sf, @color))
    @drawable.append(SF::Vertex.new(@dst.sf, @color))
  end

  def self.z_index
    -1
  end

  def sync
    @drawable = SF::VertexArray.new(SF::Lines)
    @drawable.append(SF::Vertex.new(@src.mid.sf, @color))
    @drawable.append(SF::Vertex.new(@dst.sf, @color))
  end

  def distribute(message : Message, color : SF::Color, strength : Float)
    @tank.distribute(@dst, message, color, strength, deadzone: 1)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    @drawable.draw(target, states)
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

      a.smack(b)
      b.smack(a)

      true
    end
  end

  @scatterer : UUID

  def initialize
    @space = CP::Space.new
    @space.use_spatial_hash(dim: 4, count: 4096)
    @space.damping = 0.3
    @space.gravity = CP.v(0, 0)

    @entities = EntityCollection.new
    @bodies = {} of UInt64 => PhysicalEntity

    @entropy = OpenSimplexNoise.new
    @stime = 1i64

    @watch = TimeTable.new(App.time)

    # Compute milliseconds between 0..2000 by scaling turbulence.
    @scatterer = @watch.every(((1 - self.class.turbulence) * 2000).milliseconds) do
      @stime += 1
    end

    dispatcher = TankDispatcher.new(self)

    @space.add_collision_handler(dispatcher)
  end

  # Turbulence factor [0; 1] determines how often entropy time is incremented.
  # Entropy time is the third dimension of entropy. The other two are the X, Y
  # coordinates of the sampled point.
  def self.turbulence
    0.4
  end

  @lens : Lens = Lens::Blurred.new

  def inspecting?(object : Inspectable?)
    @lens.aiming_at?(object)
  end

  def inspect(object : Inspectable?)
    @lens = @lens.focus(object)
  end

  def handle(event : SF::Event)
    @lens.forward(event)
  end

  def follow(view : SF::View)
    @lens.configure(view)
  end

  def entropy(at pos : Vector2)
    @entropy.generate(pos.x/100, pos.y/100, @stime/10) * 0.5 + 0.5
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
    @entities.insert(entity)
  end

  def remove(entity : Entity, object : CP::Shape | CP::Body)
    @space.remove(object)
    if object.is_a?(CP::Body)
      @bodies.delete(object.object_id)
    end
  end

  def remove(entity : Entity)
    @entities.delete(entity)
  end

  def cell(*, to pos : Vector2)
    cell = CellAvatar.new(self, cell: Cell.new)
    cell.mid = pos
    cell.summon
    cell
  end

  def vein(*, to pos : Vector2)
    vein = Vein.new(self)
    vein.mid = pos
    vein.summon
    vein
  end

  def wire(*, from cell : CellAvatar, to pos : Vector2)
    wire = Wire.new(self, cell, pos)
    cell.add_wire(wire)
    wire.summon
    wire
  end

  def each_entity
    @entities.each do |entity|
      yield entity
    end
  end

  def each_entity_by_z_index
    @entities.each_by_z_index do |entity|
      yield entity
    end
  end

  def each_cell
    @entities.each(CellAvatar) do |cell|
      yield cell
    end
  end

  def each_vein
    @entities.each(Vein) do |vein|
      yield vein
    end
  end

  def find_entity_by_id?(id : UUID)
    @entities[id]?
  end

  def find_entity_by_body?(body : CP::Body)
    @bodies[body.object_id]?
  end

  def find_entity_at?(pos : Vector2)
    @entities.at?(pos)
  end

  def find_cell_at?(pos : Vector2)
    @entities.at?(CellAvatar, pos)
  end

  def distribute(origin : Vector2, message : Message, color : SF::Color, strength : Float, deadzone = CellAvatar.radius * 1.2)
    vamt = fmessage_amount(strength)

    return unless vamt.in?(1.0..1024.0) # safety belt

    vrays = Math.max(1, vamt // 2)

    vamt = vamt.to_i
    vrays = vrays.to_i
    vlifespan = fmessage_lifespan_ms(strength).milliseconds

    vamt.times do |v|
      angle = Math.radians(((v / vrays) * 360) + rand * 360)
      vesicle = Vesicle.new(self, message, angle, strength, vlifespan, color, birth: Time.monotonic)
      vesicle.mid = origin + (angle.dir * deadzone)
      vesicle.summon
    end
  end

  def distribute_vein_bi(origin : Vector2, message : Message, color : SF::Color, lifespan : Time::Span, strength : Float)
    vamt = 2
    vrays = 2

    vamt.times do |v|
      angle = Math.radians(((v / vrays) * 360))
      vesicle = Vesicle.new(self, message, angle, strength, lifespan, color, birth: Time.monotonic, randomize: false)
      if v.even?
        vesicle.mid = origin + (angle.dir * Vein.width)
      else
        vesicle.mid = origin + angle.dir
      end
      vesicle.summon
    end
  end

  def tick(delta : Float)
    @watch.tick
    @space.step(delta)

    each_entity &.tick(delta)

    each_cell &.systole
    each_cell &.dyastole
  end

  JCIRC = SF::CircleShape.new(point_count: 10)

  @emap = SF::RenderTexture.new
  @emap_hash : UInt64?
  @emap_time = 0

  @vesicles_texture = SF::RenderTexture.new
  @vesicles_hash : UInt64?

  def draw(what : Symbol, target : SF::RenderTarget)
    case what
    when :entities
      view = target.view

      top_left = view.center - SF.vector2f(view.size.x/2, view.size.y/2)
      bot_right = top_left + view.size
      extent = bot_right - top_left

      vesicles_hash = {top_left, bot_right}.hash

      unless vesicles_hash == @vesicles_hash
        # Recreate vesicles texture if size changed. Become the
        # same size as target.
        @vesicles_texture.create(extent.x.to_i, extent.y.to_i)
      end

      @vesicles_hash = vesicles_hash
      @vesicles_texture.view = view
      @vesicles_texture.clear(SF::Color.new(0x21, 0x21, 0x21, 0))

      #
      # Draw entities ordered by their z index.
      #
      each_entity_by_z_index do |entity|
        next if @lens.aiming_at?(entity)

        (entity.is_a?(Vesicle) ? @vesicles_texture : target).draw(entity)
      end

      @vesicles_texture.display

      sprite = SF::Sprite.new(@vesicles_texture.texture)
      sprite.position = top_left
      target.draw(sprite)

      # Then draw the inspected entity. This is done so that
      # the inspected entity is in front, that is, drawn on
      # top of everything else.
      @lens.each { |entity| target.draw(entity) }
    when :entropy
      #
      # Draw jitter map for the visible area.
      #
      view = target.view

      top_left = view.center - SF.vector2f(view.size.x/2, view.size.y/2)
      bot_right = top_left + view.size
      extent = bot_right - top_left

      emap_hash = {top_left, bot_right}.hash

      # Do not draw if extent is the same and time is the same.
      unless emap_hash == @emap_hash && @stime == @emap_time
        unless emap_hash == @emap_hash
          # Recreate emap texture if size changed. Become the
          # same size as target.
          @emap.create(extent.x.to_i, extent.y.to_i, settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
        end

        @emap_hash = emap_hash
        @emap_time = @stime

        # View the same region as target.
        @emap.view = view
        @emap.clear(SF::Color.new(0x21, 0x21, 0x21, 0))

        step = 12.at(12)

        vectors = [] of SF::Vertex

        top_left.y.step(to: bot_right.y, by: step.y) do |y|
          top_left.x.step(to: bot_right.x, by: step.x) do |x|
            jrect_origin = x.at(y)
            jrect_mid = jrect_origin + step/2

            sample = entropy(jrect_mid)
            fill = SF::Color.new(*LCH.lch2rgb(l = sample * 30 + 10, 0, 0))
            next if l <= 12

            JCIRC.position = jrect_origin.sf
            JCIRC.radius = (step.x/2 - 1) * sample + 1
            JCIRC.fill_color = fill
            @emap.draw(JCIRC)
          end
        end

        @emap.display
      end

      sprite = SF::Sprite.new(@emap.texture)
      sprite.position = top_left
      target.draw(sprite)
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
  def initialize(@elevated : CellAvatar? = nil, @ondrop : Mode = self)
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

    # If a cell is being inspected and cursor is in bounds of
    # its editor, redirect.

    app.tank.@lens.each do |object|
      next unless object.is_a?(CellAvatar) && object.point_in_editor?(coords)

      event.x = coords.x.to_i - object.editor_position.x.to_i
      event.y = coords.y.to_i - object.editor_position.y.to_i
      object.handle(event)

      return self
    end

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
        keyword: "mouse",
        args: [] of Memorable,
      ), SF::Color.new(*(@clicks == 2 ? {0xf7, 0x9b, 0x98} : {0xc1, 0x6b, 0x69})), strength: @clicks == 2 ? 250.0 : 130.0, deadzone: 1)
    end

    self
  end

  def map(app, event : SF::Event::MouseButtonReleased)
    coords = app.coords(event)
    # If a cell is being inspected and cursor is in bounds of
    # its editor, redirect.
    app.tank.@lens.each do |object|
      next unless object.is_a?(CellAvatar) && object.point_in_editor?(coords)

      event.x = coords.x.to_i - object.editor_position.x.to_i
      event.y = coords.y.to_i - object.editor_position.y.to_i
      object.handle(event)

      return self
    end

    if @elevated.nil? && (@mouse_in_tank.in?(app.console) || app.console.elevated?)
      app.console.handle(event)
      return self
    end

    @elevated.try &.halt
    @elevated = nil

    @ondrop
  end

  def map(app, event : SF::Event::MouseMoved)
    super
    coords = app.coords(event)

    # If a cell is being inspected and cursor is in bounds of
    # its editor, redirect.
    app.tank.@lens.each do |object|
      next unless object.is_a?(CellAvatar) && object.point_in_editor?(coords)

      event.x = coords.x.to_i - object.editor_position.x.to_i
      event.y = coords.y.to_i - object.editor_position.y.to_i
      object.handle(event)

      return self
    end

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

    app.pan((-event.delta * 10).y)

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

  @pressed_on : CellAvatar?

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
        released_on.suicide
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

record WireConfig, from : CellAvatar? = nil, to : Vector2? = nil

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

  def submit(app : App, src : CellAvatar, dst : Vector2)
    app.tank.wire(from: src, to: dst)
  end

  def map(app, event : SF::Event::MouseWheelScrolled)
    app.pan((-event.delta * 10).x)

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

  def map(app, event : SF::Event::KeyPressed)
    case event.code
    when .j?
      App.the.heightmap = !App.the.heightmap?
    else
      return super
    end

    self
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
        copy = cell.replicate(to: coords)
        app.tank.inspect(copy)
        return Mode::Normal.new(elevated: copy, ondrop: self)
      end
    end
    self
  end

  def map(app, event : SF::Event::MouseWheelScrolled)
    event.delta < 0 ? app.zoom_smaller : app.zoom_bigger

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

  property? heightmap = false

  @mode : Mode

  private def mode=(other : Mode)
    return if @mode.same?(other)

    other.unload(self)
    @mode = other
    @mode.load(self)
  end

  def initialize
    @editor = SF::RenderTexture.new(1280, 720, settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @hud = SF::RenderTexture.new(1280, 720, settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))

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

  def pan(delta : Vector2)
    view = @editor.view
    view.center += delta.sf
    view.center = SF.vector2f(view.center.x.round, view.center.y.round)
    @editor.view = view
  end

  def follow
    @editor.view = @tank.follow(@editor.view)
  end

  ZOOMS = {0.1, 0.3, 0.5, 1.0, 1.3, 1.5, 1.7, 1.9, 2.0}

  @zoom : Int32 = ZOOMS.index!(1.0)

  def zoom_bigger
    @zoom = Math.max(0, @zoom - 1)

    setzoom(ZOOMS[@zoom])
  end

  def zoom_smaller
    @zoom = Math.min(ZOOMS.size - 1, @zoom + 1)

    setzoom(ZOOMS[@zoom])
  end

  def setzoom(factor : Number)
    view = SF::View.new
    view.center = SF.vector2f(@editor.view.center.x.round, @editor.view.center.y.round)
    view.size = SF.vector2f(@editor.size.x, @editor.size.y)
    view.zoom(factor)
    @editor.view = view
  end

  def unzoom
    @zoom = ZOOMS.index!(1.0)

    setzoom(1.0)
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

    @tank.draw(:entropy, @editor) if heightmap?
    @tank.draw(:entities, @editor)
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
          view.zoom(ZOOMS[@zoom])
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

      while @scene_window.open? && (event = @scene_window.poll_event)
        case event
        when SF::Event::Closed
          @scene_window.close
        when SF::Event::KeyPressed
          @tank.each_vein &.emit("key", [event.code.to_s] of Memorable, color: CellAvatar.color(l: 80, c: 70))
        when SF::Event::TextEntered
          chr = event.unicode.chr
          if chr.printable?
            @tank.each_vein &.emit("chr", [chr.to_s] of Memorable, color: CellAvatar.color(l: 80, c: 70))
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
# [x] add die() to kill current cell programmatically
# [x] add replicate() to copy cell programmaticaly
# [x] introduce "entropy": every entity samples 3d noise (x, y, time) to
#     get a "jitter" value.
# [x] introduce the entropy device; set jitter using jitter()
# [x] read entropy using entropy()
# [x] add visualization for "entropy"; toggle on C-j
# [x] introduce ascend() to select whether a cell should climb up/down
# [x] use 'express' terminology instead of 'response', 'execute', 'eval'
#     'answer' for rules
# [x] rename ResponseContext to ExpressionContext, move it & children
#     to another file
# [x] use fixed zoom steps for text rendering without fp errors
# [x] move protocol, rule, signatures to a different file
# [x] make entity#drawable and entity#drawing stuff a module rather
#     than what comes when subclassing eg entity or physical entity.
#     this puts a huge restriction on what and how we can draw
# [x] represent vesicles using one SF::Points vertex (at least try
#     and see if it improves performance)
# [ ] isolate protocol, rule, signatures
# [ ] add heartbeatresponsecontext, attack there is circmean attacks
#     weighted by amount (group attack angles by proximity, at
#     systoles count weights for each group & compute wcircmean
#     over circmeans of groups?), evasion conversely
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
# [ ] add concentration device to heartbeatresponsecontext which
#     is a value based on the change of the amount of vesicles
#     hitting the cell between systoles (???)
# [ ] refactor, simplify, remove useless method dancing? use smaller
#     objects, object-ize everything, get rid of getters and properties
#     in Cell, e.g. refactor all methods that use (*, in tank : Tank) to a
#     separate object e.g. CellView
# [ ] implement save/load for the small objects & the system overall: save/load image feature
# [x] split into different files, use Crystal structure
# [ ] optimize?
# [ ] write a few examples, record using GIF
# [ ] write README with gifs
# [x] upload to GH

App.the.run
