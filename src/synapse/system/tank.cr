abstract class Tank
  class TankDispatcher < CP::CollisionHandler
    def initialize(@tank : Tank)
      super()
    end

    def begin(arbiter : CP::Arbiter, space : CP::Space)
      ba, bb = arbiter.bodies

      return true unless a = @tank.find_entity_by_body?(ba)
      return true unless b = @tank.find_entity_by_body?(bb)

      a.smack(b)
      b.smack(a)

      true
    end
  end

  @lens : Lens = Lens::Blurred.new

  def initialize
    @space = CP::Space.new
    @bodies = {} of UInt64 => PhysicalEntity
    @entities = EntityCollection.new

    dispatcher = TankDispatcher.new(self)

    @space.add_collision_handler(dispatcher)
  end

  def print(string : String)
  end

  def clock_authority
    ClockAuthority.new # TODO: make this actually the authority for the rest of stuff
  end

  def inspecting?(object : Inspectable?)
    @lens.aiming_at?(object)
  end

  def inspect(object : Inspectable?)
    @lens = @lens.focus(object)
  end

  def handle(event : SF::Event)
    @lens.forward(event)
  end

  def follow(view : SF::View)
    @lens.configure(view)
  end

  def each_entity
    @entities.each do |entity|
      yield entity
    end
  end

  def each_entity_by_z_index
    @entities.each_by_z_index do |entity|
      yield entity
    end
  end

  def find_entity_by_id?(id : UUID)
    @entities[id]?
  end

  def find_entity_by_body?(body : CP::Body)
    @bodies[body.object_id]?
  end

  def find_entity_at?(pos : Vector2)
    @entities.at?(pos)
  end

  def insert(entity : Entity, object : CP::Shape | CP::Body)
    @space.add(object)
    if object.is_a?(CP::Body)
      @bodies[object.object_id] = entity
    end
  end

  def insert(entity : Entity)
    @entities.insert(entity)
  end

  def remove(entity : Entity, object : CP::Shape | CP::Body)
    @space.remove(object)
    if object.is_a?(CP::Body)
      @bodies.delete(object.object_id)
    end
  end

  def remove(entity : Entity)
    @entities.delete(entity)
  end

  def entropy(position : Vector2)
    0.0
  end

  def distribute(origin : Vector2, message : Message, color : SF::Color, strength : Float, deadzone = CellAvatar.radius * 1.2)
    vamt = fmessage_amount(strength)

    return unless vamt.in?(1.0..1024.0) # safety belt

    vrays = Math.max(1, vamt // 2)

    vamt = vamt.to_i
    vrays = vrays.to_i
    vlifespan = fmessage_lifespan_ms(strength).milliseconds

    vamt.times do |v|
      angle = Math.radians(((v / vrays) * 360) + rand * 360)
      vesicle = Vesicle.new(self, message, angle, strength, vlifespan, color, birth: Time.monotonic)
      vesicle.mid = origin + (angle.dir * deadzone)
      vesicle.summon
    end
  end

  def tick(delta : Float)
    @space.step(delta)

    each_entity &.tick(delta)
  end

  @vesicles_texture = SF::RenderTexture.new
  @vesicles_hash : UInt64?

  def draw(what : Symbol, target : SF::RenderTarget)
    view = target.view

    top_left = view.center - SF.vector2f(view.size.x/2, view.size.y/2)
    bot_right = top_left + view.size
    extent = bot_right - top_left

    vesicles_hash = {top_left, bot_right}.hash

    unless vesicles_hash == @vesicles_hash
      # Recreate vesicles texture if size changed. Become the
      # same size as target.
      @vesicles_texture.create(extent.x.to_i, extent.y.to_i)
    end

    @vesicles_hash = vesicles_hash
    @vesicles_texture.view = view
    @vesicles_texture.clear(SF::Color.new(0x21, 0x21, 0x21, 0))

    vesicles = SF::VertexArray.new(SF::Points, @entities.count(Vesicle))

    @entities.each(Vesicle) do |vesicle|
      vesicles.append(vesicle.to_vertex)
    end

    @vesicles_texture.draw(vesicles)

    #
    # Draw entities ordered by their z index.
    #
    @entities.each_by_z_index(except: {Vesicle}) do |entity|
      next if @lens.aiming_at?(entity)
      next unless entity.is_a?(SF::Drawable)

      target.draw(entity)
    end

    @vesicles_texture.display

    sprite = SF::Sprite.new(@vesicles_texture.texture)
    sprite.position = top_left
    target.draw(sprite)

    # Then draw the inspected entity. This is done so that
    # the inspected entity is in front, that is, drawn on
    # top of everything else.
    @lens.each { |entity| target.draw(entity) }
  end
end
