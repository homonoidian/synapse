# :nodoc:
module IPhysicalBodyClass
  # Creates and returns a `CP::Body` object corresponding to
  # this kind of entity.
  abstract def body : CP::Body
end

module IEntropyProvider
  abstract def entropy(position : Vector2)
end

# Physical entities are entities with a physical body, that is,
# entities with a number of physical attributes, such as position,
# velocity, mass, etc.
abstract class PhysicalEntity < Entity
  extend IPhysicalBodyClass

  # Introduces jitter to the motion of the includer entity.
  module Jitter
    # Jitter: willingness to change entropy elevation [0; 1]
    property jitter = 0.0

    # Jitter ascent mix (0.0 = descent, 1.0 = ascent).
    property jascent = 0.0

    # Returns an iterable of angles that should be sampled when
    # computing jitter motion.
    abstract def jangles

    def tick(delta : Float)
      super

      return if @jitter.zero?
      return unless tank = @tank.as?(IEntropyProvider)

      samples = jangles.map { |angle| {angle, tank.entropy(mid + self.class.radius + angle.dir * self.class.radius)} }

      min_hdg, _ = samples.min_by { |_, entropy| entropy }
      max_hdg, _ = samples.max_by { |_, entropy| entropy }

      #
      # Compute weighed mean to get heading
      #
      ascent_w = @jascent
      descent_w = 1 - @jascent

      sines = 0
      cosines = 0

      sines += ascent_w * Math.sin(Math.radians(max_hdg))
      cosines += ascent_w * Math.cos(Math.radians(max_hdg))

      sines += descent_w * Math.sin(Math.radians(min_hdg))
      cosines += descent_w * Math.cos(Math.radians(min_hdg))

      heading = Math.degrees(Math.atan2(sines, cosines))

      #
      # Compute flow vector and flow scale.
      #
      flow_vec = heading.dir
      flow_scale = @tank.magn_to_flow_scale(velocity.zero? ? 10 * @jitter : velocity.magn)

      @body.velocity += (flow_vec * flow_scale).cp * @jitter
    end
  end

  @body : CP::Body

  def initialize(tank : Tank, color : SF::Color, lifespan : Time::Span?)
    super(tank, color, lifespan)

    @body = self.class.body
  end

  # Specifies the mass of this entity.
  def self.mass
    10.0
  end

  # Holds the position of this entity.
  #
  # Note: for `MorphEntity` and subclasses, holds the coordinates of
  # the center of their shapes. `PhysicalEntity` on its own is more like
  # a point, not a shape, therefore, we can't say it has a "center".
  def mid
    @body.position.x.round.at(@body.position.y.round)
  end

  # :ditto:
  def mid=(mid : Vector2)
    @body.position = mid.cp
  end

  # Holds the velocity of this entity.
  def velocity
    @body.velocity.x.at(@body.velocity.y)
  end

  # :ditto:
  def velocity=(velocity : Vector2)
    @body.velocity = velocity.cp
  end

  # Brings this entity to an abrupt stop.
  def halt
    @body.velocity = 0.at(0).cp
  end

  def summon
    super

    @tank.insert(self, @body)

    nil
  end

  def dismiss
    super

    @tank.remove(self, @body)

    nil
  end

  # Returns a sample [0; 1] of entropy at this entity's position.
  def entropy
    return 0.0 unless tank = @tank.as?(IEntropyProvider)

    tank.entropy(mid)
  end

  # Called when this and *other* entities collide.
  def acknowledge(other : PhysicalEntity)
  end
end
