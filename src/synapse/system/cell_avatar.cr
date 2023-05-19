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

  def initialize(tank : Tank, @cell : Cell, color : SF::Color, @browser : AgentBrowserHub)
    super(tank, color, lifespan: nil)

    @drawable = SF::CircleShape.new
    @drawable.fill_color = @color
    @drawable.radius = self.class.radius
  end

  def initialize(tank : Tank, cell : Cell, browser : AgentBrowserHub)
    initialize(tank, cell,
      color: self.class.color,
      browser: browser,
    )
  end

  delegate :memory, :each_owned_protocol_with_name, :pack, to: @cell

  def adhere(*args, **kwargs)
    @cell.adhere(@browser, *args, **kwargs) do |agent|
      @browser.register(@cell, agent)
    end
  end

  def jangles
    {0, 45, 90, 135, 180, 225, 270, 315}
  end

  def point_in_editor?(point : Vector2)
    origin = Vector2.new(editor_position)
    corner = origin + @browser.size
    origin.x <= point.x <= corner.x && origin.y <= point.y <= corner.y
  end

  def self.radius
    8
  end

  def self.mass
    1e5
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
    _, _, h = LCH.rgb2lch(@color.r, @color.g, @color.b)

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
      @cell.unfail
      return
    end

    fail(result)
  end

  def replicate_with_select_protocols(to coords = mid, &)
    recipient = AgentGraph.new(Protoplasm.new)

    @cell.selective_fill(recipient) do |protocol|
      !!(yield protocol)
    end

    replica = CellAvatar.new(@tank, @cell.copy(recipient), @color, @browser)
    replica.mid = coords
    replica.summon
    replica
  end

  def replicate(to coords = mid) : CellAvatar
    replicate_with_select_protocols(to: coords) { true }
  end

  def summon
    super

    @cell.born(avatar: self)
    @browser.register(@cell)

    nil
  end

  def dismiss
    super

    @cell.died(avatar: self)
    @browser.unregister(@cell)

    nil
  end

  def receive(vesicle : Vesicle)
    @cell.receive(avatar: self, vesicle: vesicle)
  rescue CommitSuicide
    dismiss
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

    err.agent.fail(err.error.message || "lua error")
  end

  def handle(event)
    @browser.handle(event)
  end

  def editor_position
    (mid + 32.at(32)).sfi
  end

  def focus
    @browser.browse(@cell)
  end

  def blur
    @browser.upload(@cell)
  end

  def tick(delta : Float)
    super

    @cell.tick(delta, avatar: self)
  rescue CommitSuicide
    dismiss
  end

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
      bg_rect.size = @browser.size.sf + SF.vector2f(4, 2)
      target.draw(bg_rect)

      #
      # Draw a line from origin of background to the center of
      # the cell.
      #
      va = SF::VertexArray.new(SF::Lines, 2)
      va.append(SF::Vertex.new(mid.sfi, sync_color_opaque))
      va.append(SF::Vertex.new(bg_rect.position, sync_color_opaque))
      target.draw(va)

      @browser.position = Vector2.new(editor_position)
      target.draw(@browser)
    end
  end
end
