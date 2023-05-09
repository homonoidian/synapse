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
