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

  def print(string : String)
    @tank.print(string)
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
