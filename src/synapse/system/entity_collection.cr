# A collection of `Entity` objects.
#
# Supports retrieval of entities by ID. Stores each type of
# entity in a separate sub-collection, meaning you can iterate
# over a specific kind of entity (e.g. `Cell`) without having
# to iterate over all entities.
class EntityCollection
  @entities = {} of Entity.class => Hash(UUID, Entity)

  # Returns the amount of entities in this collection.
  def size
    @entities.sum { |_, hash| hash.size }
  end

  # Returns the entity with the given *id*, or nil if there
  # is no such entity.
  def []?(id : UUID)
    @entities.find(&.[id]?)
  end

  # Returns the entity at the given *position*, or nil if there
  # is no entity there.
  def at?(position : Vector2)
    each { |entity| return entity if position.in?(entity) }
  end

  # Returns the entity of type `T` at *position*, or nil if
  # there is no such entity there.
  def at?(type : T.class, position : Vector2) : T? forall T
    each(T) { |cell| return cell.as(T) if position.in?(cell) }
  end

  # Inserts *entity* of the given *type* under *id* into
  # this collection.
  def insert(type : Entity.class, id : UUID, entity : Entity)
    (@entities[type] ||= {} of UUID => Entity)[id] = entity
  end

  # Inserts *entity* into this collection.
  def insert(entity : Entity)
    entity.insert(into: self)
  end

  # Deletes *entity* of *type* with the given *id*  from
  # this collection.
  def delete(type : Entity.class, id : UUID, entity : Entity)
    @entities[type]?.try &.delete(id)
  end

  # Deletes *entity* from this collection.
  def delete(entity : Entity)
    entity.delete(from: self)
  end

  # Yields all entities in this collection.
  def each
    @entities.each do |_, store|
      store.each_value do |entity|
        yield entity
      end
    end
  end

  # Yields all entities in this collection ordered by their
  # Z-index, ascending (first is bottom, and last is top).
  def each_by_z_index
    entities = Array(Entity).new(size)
    each do |entity|
      entities << entity
    end

    entities.unstable_sort_by!(&.z_index)
    entities.each do |entity|
      yield entity
    end
  end

  # Yields all entities of type `T` in this collection.
  def each(type : T.class) forall T
    return unless store = @entities[T]?

    store.each_value do |entity|
      yield entity.as(T)
    end
  end
end
