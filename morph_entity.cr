# :nodoc:
module IMorphEntityClass
  # Creates and returns a `CP::Shape` object corresponding to
  # this kind of entity, given its *body*.
  abstract def shape(body : CP::Body) : CP::Shape
end

# Morph entities are entities with physics and appearance.
abstract class MorphEntity < PhysicalEntity
  extend IMorphEntityClass

  @shape : CP::Shape

  def initialize(color : SF::Color, lifespan : Time::Span?)
    super(color, lifespan)

    @shape = self.class.shape(@body)
  end

  # Specifies the friction of this entity.
  def self.friction
    10.0
  end

  # Specifies the elasticity of this entity.
  def self.elasticity
    0.4
  end

  def summon(in tank : Tank)
    super

    tank.insert(self, @shape)

    nil
  end

  def suicide(in tank : Tank)
    super

    tank.remove(self, @shape)

    nil
  end

  # Returns the width of this entity in pixels.
  abstract def width : Number

  # Returns the height of this entity in pixels.
  abstract def height : Number

  # Returns whether *point* lies in the bounds of this entity.
  def includes?(point : Vector2)
    point.x.in?(mid.x - width//2..mid.x + width//2) &&
      point.y.in?(mid.y - height//2..mid.y + height//2)
  end
end
