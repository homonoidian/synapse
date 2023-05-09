# A circular entity is an entity that has a circle appearance.
abstract class CircularEntity < MorphEntity
  def self.body : CP::Body
    moment = CP::Circle.moment(mass, 0.0, radius)

    CP::Body.new(mass, moment)
  end

  def self.shape(body : CP::Body) : CP::Shape
    shape = CP::Circle.new(body, radius)
    shape.friction = friction
    shape.elasticity = elasticity
    shape
  end

  # Specifies the radius of this circular entity.
  def self.radius
    4
  end

  def width : Number
    self.class.radius*2
  end

  def height : Number
    self.class.radius*2
  end
end
