abstract class Tank
  class TankDispatcher < CP::CollisionHandler
    def initialize(@tank : Tank)
      super()
    end

    def begin(arbiter : CP::Arbiter, space : CP::Space)
      ba, bb = arbiter.bodies

      return true unless a = @tank.find_entity_by_body?(ba)
      return true unless b = @tank.find_entity_by_body?(bb)

      a.acknowledge(b)
      b.acknowledge(a)

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

  def strength_to_vesicle_count(strength : Float)
    # https://www.desmos.com/calculator/bk3g3l6txg

    if strength <= 80
      1.8256 * Math.log(strength)
    elsif strength <= 150
      6/1225 * (strength - 80)**2 + 8
    else
      8 * Math.log(strength - 95.402)
    end
  end

  def strength_to_vesicle_lifespan(strength : Float)
    # https://www.desmos.com/calculator/rzukaixbsx
    if strength <= 155
      2000 * Math::E**(-strength/60)
    elsif strength <= 700
      Math::E**(strength/100) + 146
    else
      190 * Math.log(strength)
    end
  end

  def strength_to_jitter_mix(strength : Float)
    strength.in?(0.0..1000.0) ? 1 - (1/1000 * strength**2)/1000 : 0.0
  end

  def magn_to_flow_scale(magn : Float)
    if 3.684 <= magn
      50/magn
    elsif magn > 0
      magn**2
    else
      0
    end
  end

  def print(string : String)
  end

  def inspecting?(object : Inspectable?)
    @lens.aiming_at?(object)
  end

  def inspect(object : Inspectable?)
    inspect(object) { }
  end

  def inspect(object : Inspectable?, &)
    @lens.focus(object) do |lens|
      @lens = lens
      yield
    end
  end

  def handle(event : SF::Event)
    @lens.forward(event)
  end

  def each_entity(&)
    @entities.each do |entity|
      yield entity
    end
  end

  def each_entity(type : T.class, &) forall T
    @entities.each(T) do |entity|
      yield entity
    end
  end

  def each_entity_by_z_index(&)
    @entities.each_by_z_index do |entity|
      yield entity
    end
  end

  def find_entity_by_id?(id : App::Id)
    @entities[id]?
  end

  def find_entity_by_body?(body : CP::Body)
    @bodies[body.object_id]?
  end

  def find_entity_at?(pos : Vector2)
    @entities.at?(pos)
  end

  def find_at?(pos : Vector2)
    @entities.at?(pos)
  end

  def find_at?(pos : Vector2, type : T.class) forall T
    @entities.at?(T, pos)
  end

  def insert(entity : Entity, object : CP::Shape | CP::Body)
    @space.add(object)
    if object.is_a?(CP::Body)
      @bodies[object.object_id] = entity
    end
  end

  def insert(constraint : CP::Constraint)
    @space.add(constraint)
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

  def remove(constraint : CP::Constraint)
    @space.remove(constraint)
  end

  def remove(entity : Entity)
    @entities.delete(entity)
  end

  def entropy(position : Vector2)
    0.0
  end

  # Returns growth rate or population size slope.
  getter growth = 1.0

  @population = 1

  def tick(delta : Float)
    super

    @population, prev = @entities.size, @population
    @growth = @population / prev
  end

  def growth_modulate(x)
    1/growth * x
  end

  def distribute(origin : Vector2, message : Message, color : SF::Color, strength : Float, deadzone = CellAvatar.radius * 1.2)
    vamt = strength_to_vesicle_count(strength)
    vamt = growth_modulate(vamt)

    return unless vamt.in?(1.0..512.0) # safety belt

    lifespan = strength_to_vesicle_lifespan(strength)
    lifespan = growth_modulate(lifespan)

    vrays = Math.max(1, vamt // 2)
    vamt = vamt.to_i
    vrays = vrays.to_i
    vlifespan = lifespan.milliseconds + (-50..100).sample.milliseconds

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

  @vesicles = [] of SF::Vertex

  def draw(what : Symbol, target : SF::RenderTarget)
    view = target.view

    top_left = view.center - SF.vector2f(view.size.x//2, view.size.y//2)
    bot_right = top_left + view.size

    vesicles_hash = {top_left, bot_right}.hash

    unless vesicles_hash == @vesicles_hash
      extent = bot_right - top_left
      # Recreate vesicles texture if size changed. Become the
      # same size as target.
      @vesicles_texture.create(extent.x.to_i, extent.y.to_i)
    end

    @vesicles_hash = vesicles_hash
    @vesicles_texture.clear(SF::Color.new(0x21, 0x21, 0x21, 0))
    @vesicles_texture.view = SF::View.new(view.center, view.size)

    @vesicles.clear
    @entities.each(Vesicle) do |vesicle|
      @vesicles << vesicle.to_vertex
    end

    @vesicles_texture.draw(@vesicles, SF::Points)
    @vesicles_texture.display

    #
    # Draw entities ordered by their z index.
    #
    @entities.each_by_z_index(except: {Vesicle}) do |entity|
      next if @lens.aiming_at?(entity)
      next unless entity.is_a?(SF::Drawable)

      target.draw(entity)
    end

    sprite = SF::Sprite.new(@vesicles_texture.texture)
    sprite.position = top_left
    target.draw(sprite)

    # Then draw the inspected entity. This is done so that
    # the inspected entity is in front, that is, drawn on
    # top of everything else.
    @lens.each { |entity| target.draw(entity) }
  end
end
