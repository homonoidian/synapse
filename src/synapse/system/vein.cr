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
