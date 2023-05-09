class Vesicle < CircularEntity
  include SF::Drawable
  include Jitter

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
