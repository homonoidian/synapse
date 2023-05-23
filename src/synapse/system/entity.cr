# Entity is the base class of all that "exists" and can "die"
# in the Synapse world, implicitly or explicitly -- that is,
# with or without a "body", "shape", or an "image" that the
# user can see or interact with.
#
# Notably, all entities have a color and a globally unique ID.
# The latter is the only thing that actually differentiates
# entities under the hood.
abstract class Entity
  @id : App::Id
  @decay : App::ControlledTimeout?

  def initialize(@tank : Tank, @color : SF::Color, lifespan : Time::Span?)
    # Unique ID of this entity.
    #
    # All entities (including vesicles!) have a unique ID so
    # that the system can address them.
    @id = App.genid

    return unless lifespan

    decay = App::ControlledTimeout.new(lifespan, &->dismiss)
    decay.publish
    @decay = decay
  end

  # Specifies the z-index of this kind of entity, that is, how
  # it should be drawn in relation to other entities on the Z
  # axis (i.e. above or below or on the same level).
  def self.z_index
    0
  end

  # Specifies the z-index of this particular entity.
  #
  # See `Entity.z_index`.
  def z_index
    self.class.z_index
  end

  # Returns a float [0; 1] describing how close this entity
  # is to death (e.g. 0 means it's newborn, and 1 means it's
  # about to die).
  def decay
    @decay.try &.progress || 0.0
  end

  # Spawns this entity in the tank.
  #
  # Be careful not to call this method if this entity is already in the tank.
  def summon
    @tank.insert(self)

    nil
  end

  # Removes this entity from the tank.
  #
  # Be careful not to call this method if this entity is not in the tank.
  def dismiss
    @decay.try &.cancel
    @decay = nil
    @tank.remove(self)

    nil
  end

  # Inserts this entity into the given *collection*.
  def insert(*, into collection : EntityCollection)
    collection.insert(self.class, @id, entity: self)
  end

  # Removes this entity from the given *collection*.
  def delete(*, from collection : EntityCollection)
    collection.delete(self.class, @id, entity: self)
  end

  # Progresses this entity through time in the tank.
  def tick(delta : Float)
    @decay.try &.tick(delta)
  end

  # Two entities are equal when their IDs are equal.
  def_equals_and_hash @id
end
