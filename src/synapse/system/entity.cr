# Entity is the base class of all that "exists" and can "die"
# in the Synapse world, implicitly or explicitly -- that is,
# with or without a "body", "shape", or an "image" that the
# user can see or interact with.
#
# Notably, all entities have a color and a globally unique ID.
# The latter is the only thing that actually differentiates
# entities under the hood.
abstract class Entity
  @decay : UUID

  def initialize(@tank : Tank, @color : SF::Color, lifespan : Time::Span?)
    # Unique ID of this entity.
    #
    # All entities (including vesicles!) have a unique ID so
    # that the system can address them.
    @id = UUID.random

    # This entity's personal clock.
    @watch = TimeTable.new(App.time)

    return unless lifespan

    # Remember the decay task id so that users can query it.
    #
    # Commit suicide after we're past the desired lifespan.
    @decay = @watch.after(lifespan) { suicide }
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
    @watch.progress(@decay)
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
  def suicide
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
    @watch.tick
  end

  # Two entities are equal when their IDs are equal.
  def_equals_and_hash @id
end
