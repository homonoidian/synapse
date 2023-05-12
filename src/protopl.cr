require "colorize"

require "crsfml"
require "chipmunk"
require "lua"
require "lch"

require "./synapse/ext"

module CellEditorEntity # FIXME: ???
  delegate :position, :position=, to: @view

  def size
    @view.size
  end

  def move(position : SF::Vector2)
    @view.position = position.round

    refresh
  end

  def lift
  end

  def drop
  end
end

FONT        = SF::Font.from_memory({{read_file("./fonts/code/scientifica.otb")}}.to_slice)
FONT_BOLD   = SF::Font.from_memory({{read_file("./fonts/code/scientificaBold.otb")}}.to_slice)
FONT_ITALIC = SF::Font.from_memory({{read_file("./fonts/code/scientificaItalic.otb")}}.to_slice)

FONT_UI        = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Regular.ttf")}}.to_slice)
FONT_UI_MEDIUM = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Medium.ttf")}}.to_slice)
FONT_UI_BOLD   = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Bold.ttf")}}.to_slice)

require "./synapse/util/*"
require "./synapse/system/lens"
require "./synapse/system/entity"
require "./synapse/system/physical_entity"
require "./synapse/system/morph_entity"
require "./synapse/system/circular_entity"
require "./synapse/system/*"

require "./synapse/ui/view"
require "./synapse/ui/dimension"
require "./synapse/ui/controller"

require "./synapse/ui/editor"
require "./synapse/ui/buffer_editor"
require "./synapse/ui/buffer_editor_row"
require "./synapse/ui/buffer_editor_column"

require "./synapse/ui/draggable"
require "./synapse/ui/rule_editor"
require "./synapse/ui/icon_view"

require "./synapse/ui/input_field"
require "./synapse/ui/input_field_row"
require "./synapse/ui/rule_header"
require "./synapse/ui/keyword_rule_header"
require "./synapse/ui/keyword_rule_editor"

require "./synapse/ui/*"

require "./ped2"

struct SF::Event::MouseButtonPressed
  property clicks : Int32 = 1
end

# ---------------------------------------------------------------------

class Protoplasm < Tank
  def initialize
    super

    @space.gravity = CP.v(0, 0)
    @space.damping = 0.4
  end

  def each_agent(& : Agent ->)
    @entities.each(Agent) do |agent|
      yield agent
    end
  end
end

module IDraggable
  abstract def lift(mouse : Vector2)
  abstract def drag(delta : Vector2, mouse : Vector2)
  abstract def drop(mouse : Vector2)
end

module IHaloSupport
  @halos = Set(Halo).new

  abstract def halo(color : SF::Color) : SF::Drawable

  def insert(halo : Halo)
    @halos << halo
  end

  def delete(halo : Halo)
    @halos.delete(halo)
  end

  def each_halo_with_drawable(&)
    @halos.each do |halo|
      next if halo.overlay?

      yield halo, halo.to_drawable
    end
  end

  def each_overlay_halo_with_drawable(&)
    @halos.each do |halo|
      next unless halo.overlay?

      yield halo, halo.to_drawable
    end
  end
end

abstract class Agent < CircularEntity
  include SF::Drawable
  include IRemixIconView
  include Inspectable
  include IDraggable
  include IHaloSupport

  @editor : Editor

  def initialize(tank : Tank)
    super(tank, self.class.color, lifespan: nil)

    @editor = to_editor
  end

  protected abstract def to_editor : Editor

  def register(viewer : AgentViewer)
    viewer.register(@editor)
  end

  def unregister(viewer : AgentViewer)
    viewer.unregister(@editor)
  end

  def title? : String?
    nil
  end

  def into(view : SF::View) : SF::View
    view
  end

  def self.radius
    16
  end

  def icon_font_size
    14
  end

  def self.color
    SF::Color.new(0x42, 0x42, 0x42)
  end

  def outline_color
    if @tank.inspecting?(self)
      SF::Color.new(0x43, 0x51, 0x80)
    else
      _, c, h = LCH.rgb2lch(icon_color.r, icon_color.g, icon_color.b)

      SF::Color.new(*LCH.lch2rgb(40, 10, h))
    end
  end

  def lift(mouse : Vector2)
  end

  def drag(delta : Vector2, mouse : Vector2)
    # We don't use delta because physics influences our position
    # too, so we want to be authoritative.
    self.mid = mouse
  end

  def drop(mouse : Vector2)
  end

  def open(*, in viewer : AgentViewer)
    return if viewer.editor_open?(@editor)

    viewer.open(self, @editor)
  end

  def compatible?(other : Agent, in viewer : AgentViewer)
    false
  end

  def halo(color : SF::Color) : SF::Drawable
    circle = SF::CircleShape.new(radius: self.class.radius * 1.3)
    circle.position = (mid - self.class.radius.xy*1.3).sf
    circle.fill_color = color
    circle
  end

  def connect(*, to other : Agent, in viewer : AgentViewer)
  end

  def spring(*, to other : Agent, **kwargs)
    other.spring(@body, **kwargs)
  end

  def spring(body : CP::Body, length : Number, stiffness : Number, damping : Number)
    CP::Constraint::DampedSpring.new(@body, body, CP.v(0, 0), CP.v(0, 0), length, stiffness, damping)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    each_halo_with_drawable { |_, drawable| target.draw(drawable) }

    circle = SF::CircleShape.new
    circle.radius = self.class.radius
    circle.position = (mid - self.class.radius.xy).sf
    circle.fill_color = @color
    circle.outline_thickness = @tank.inspecting?(self) ? 3 : 1
    circle.outline_color = outline_color
    circle.draw(target, states)

    text = icon_text
    text.position = (mid - Vector2.new(text.size)/2).sfi
    text.draw(target, states)

    each_overlay_halo_with_drawable { |_, drawable| target.draw(drawable) }

    if title = title?
      name_hint = SF::Text.new(title, FONT_UI, 11)

      name_bg = SF::RectangleShape.new
      name_bg.size = (name_hint.size + (5.at(5)*2).sfi)
      name_bg.position = (mid + self.class.radius.x*2 - name_bg.size.y/2).sf
      name_bg.fill_color = SF::Color.new(0x0, 0x0, 0x0, 0x44)
      name_bg.draw(target, states)

      name_hint.color = SF::Color.new(0xcc, 0xcc, 0xcc)
      name_hint.position = (name_bg.position + 5.at(5).sf).to_i
      name_hint.draw(target, states)
    end
  end
end

class ProtocolAgent < Agent
  def title?
    @editor.title? || "Untitled"
  end

  protected def to_editor : ProtocolEditor
    ProtocolEditor.new(ProtocolEditorState.new, ProtocolEditorView.new)
  end

  def icon
    Icon::Protocol
  end

  def icon_color
    SF::Color::White
  end

  def compatible?(other : RuleAgent, in viewer : AgentViewer)
    !viewer.has_edge?(self, other)
  end

  def connect(*, to other : RuleAgent, in viewer : AgentViewer)
    viewer.connect(self, other)
  end
end

abstract class RuleAgent < Agent
  def compatible?(other : ProtocolAgent, in viewer : AgentViewer)
    other.compatible?(self, in: viewer)
  end

  def connect(*, to other : ProtocolAgent, in viewer : AgentViewer)
    viewer.connect(other, self)
  end
end

class HeartbeatRuleAgent < RuleAgent
  delegate :title?, to: @editor

  protected def to_editor : RuleEditor
    HeartbeatRuleEditor.new(HeartbeatRuleEditorState.new, HeartbeatRuleEditorView.new)
  end

  def icon
    Icon::HeartbeatRule
  end

  def icon_color
    SF::Color.new(0xEF, 0x9A, 0x9A)
  end
end

class BirthRuleAgent < RuleAgent
  delegate :title?, to: @editor

  protected def to_editor : RuleEditor
    BirthRuleEditor.new(BirthRuleEditorState.new, BirthRuleEditorView.new)
  end

  def icon
    Icon::BirthRule
  end

  def icon_color
    SF::Color.new(0xFF, 0xE0, 0x82)
  end
end

class KeywordRuleAgent < RuleAgent
  delegate :title?, to: @editor

  protected def to_editor : RuleEditor
    KeywordRuleEditor.new(KeywordRuleEditorState.new, KeywordRuleEditorView.new)
  end

  def icon
    Icon::KeywordRule
  end

  def icon_color
    SF::Color.new(0x90, 0xCA, 0xF9)
  end
end

class Halo
  getter? overlay : Bool
  property? highlight = false

  def initialize(@viewer : AgentViewer, @recipient : IHaloSupport, @color : SF::Color, *, @overlay = false)
  end

  def summon
    @recipient.insert(self)
  end

  def dismiss
    @recipient.delete(self)
  end

  def to_drawable
    if highlight?
      _, c, h = LCH.rgb2lch(@color.r, @color.g, @color.b)
      color = SF::Color.new(*LCH.lch2rgb(70, c, h), @color.a)
    else
      color = @color
    end

    @recipient.halo(color)
  end

  def encloses?(agent : Agent)
    @recipient.same?(agent)
  end

  def includes?(point : Vector2)
    @recipient.includes?(point)
  end
end

class EndHandlingEvent < Exception
  # Returns the event whose handling should end.
  getter event : SF::Event

  def initialize(@event)
  end
end

class EventHandlerStore
  def initialize
    @registered = [] of EventHandler
  end

  def register(handler : EventHandler)
    if handler.major?
      # Put major handlers in front. Major handlers usually throw
      # the EndHandling exception to signal that event handling
      # should stop.
      @registered.unshift(handler)
    else
      @registered.push(handler)
    end
  end

  def unregister(handler : EventHandler)
    @registered.delete(handler)
  end

  def handle(event : SF::Event)
    active = @registered.dup
    active.each &.handle(event)
  rescue e : EndHandlingEvent
    raise e unless e.event == event
  end
end

abstract class EventHandler
  def initialize(@handlers : EventHandlerStore)
  end

  def major?
    false
  end

  def handle(event : SF::Event)
  end
end

class DragHandler < EventHandler
  @grip : Vector2

  def initialize(handlers : EventHandlerStore, @item : IDraggable, grip : Vector2, @oneshot = false)
    super(handlers)

    @grip = map(grip)
    @item.lift(@grip)
  end

  def map(pixel : Vector2)
    pixel
  end

  # Sends `drop` message to the item.
  def handle(event : SF::Event::MouseButtonReleased)
    @item.drop map(event.x.at(event.y))
    @handlers.unregister(self) if @oneshot # oneshot is evhcollection responsibility!
  end

  # Sends `drag` message to the item if the item is being dragged.
  def handle(event : SF::Event::MouseMoved)
    return unless grip = @grip

    coords = map(event.x.at(event.y))

    @item.drag(coords - grip, mouse: coords)
    @grip = coords
  end
end

class AgentDragHandler < DragHandler
  def initialize(@viewer : AgentViewer, *args, **kwargs)
    super(*args, **kwargs)
  end

  def map(pixel : Vector2)
    @viewer.pixel_to_protoplasm(pixel)
  end
end

class AgentViewerDispatcher < EventHandler
  def initialize(handlers : EventHandlerStore, @viewer : AgentViewer)
    super(handlers)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    return unless event.clicks == 1

    coords = Vector2.new(event.x, event.y)

    @viewer.editor_at_pixel?(coords) do |editor|
      # TODO: make editors IDraggable instead of having another Draggable module
      editor.handle(event)
      return
    end

    if agent = @viewer.find_at_pixel?(coords, entity: Agent)
      # Start inspecting the clicked-on agent, and register
      # a drag handler for it.
      @viewer.inspect(agent)

      if @shift
        cont = SingleEdgeBuilder.new(@handlers, @viewer, agent)
      else
        cont = AgentDragHandler.new(@viewer, @handlers, agent, coords, oneshot: true)
      end

      @handlers.register(cont)

      return
    end

    # If no agent to drag, register a handler to pan the protoplasm/editor.
    # Stop inspecting if we were, and the click was in the protoplasm.
    if @viewer.protoplasm_at_pixel?(coords)
      @viewer.inspect(nil)
    end

    @handlers.register DragHandler.new(@handlers, @viewer, coords, oneshot: true)
  end

  def forward(event : SF::Event)
    return unless @viewer.editor_open?

    @viewer.editor &.handle(event)
  end

  @shift = false

  def handle(event : SF::Event::KeyPressed)
    @shift = event.shift || event.code.l_shift? || event.code.r_shift?

    forward(event)
  end

  def handle(event : SF::Event::KeyReleased)
    @shift = false if event.code.l_shift? || event.code.r_shift?

    forward(event)
  end

  def handle(event : SF::Event::MouseWheelScrolled)
    @viewer.drag((@shift ? event.delta.x : event.delta.y) * 10, event.x.at(event.y))
  end

  def handle(event : SF::Event)
    forward(event)
  end
end

class EdgeCreator < EventHandler # W
  def initialize(handlers : EventHandlerStore, @viewer : AgentViewer)
    super(handlers)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    return unless event.clicks == 2

    #
    # Find out the agent on which the user clicked.
    #
    return unless agent = @viewer.find_at_pixel?(Vector2.new(event.x, event.y), entity: Agent)

    #
    # If the user indeed clicked on an agent, but nothing (of value)
    # is being inspected, switch to EdgeBuilder.
    #
    if !@viewer.@protoplasm.@lens.aiming_at?(Agent) || @viewer.@protoplasm.@lens.aiming_at?(agent)
      @handlers.register MultiEdgeBuilder.new(@handlers, @viewer, agent)
      return
    end

    #
    # Otherwise, try to connect to one of the selected agents.
    #
    @viewer.@protoplasm.@lens.each do |other|
      next unless other.is_a?(Agent)
      next unless agent.compatible?(other, in: @viewer)

      agent.connect(to: other, in: @viewer)
    end
  end
end

abstract class EdgeBuilder < EventHandler
  def initialize(handlers : EventHandlerStore, @viewer : AgentViewer, @agent : Agent)
    super(handlers)

    @edge = AgentPointEdge.new(@viewer, @agent, @agent.mid)
    @edge.summon

    @halos = [] of Halo

    #
    # Find agents that self is compatible with, and add a halo to
    # them so that the user can see where they can connect.
    #
    @viewer.each_agent do |other|
      next if @agent.same?(other)
      next unless @agent.compatible?(other, in: @viewer)

      halo = Halo.new(@viewer, other, SF::Color.new(0x43, 0x51, 0x80, 0x55), overlay: true)
      halo.summon

      @halos << halo
    end
  end

  def major?
    true
  end

  def cancel
    @edge.dismiss
    @halos.each &.dismiss
    @handlers.unregister(self)
  end

  def handle(event : SF::Event::MouseMoved)
    coords = @viewer.pixel_to_protoplasm?(event.x.at(event.y))

    return unless coords

    @edge.point = coords

    #
    # Find the halo below (if any) and lighten it a little bit.
    #
    @halos.each do |halo|
      halo.highlight = halo.includes?(coords)
    end
  end

  def handle(event : SF::Event::KeyPressed)
    case event.code
    when .escape?, .backspace?, .delete?
      cancel
    end
  end
end

class SingleEdgeBuilder < EdgeBuilder
  def handle(event : SF::Event::MouseButtonReleased)
    other = @viewer.find_at_pixel?(Vector2.new(event.x, event.y), entity: Agent)

    # If the user didn't click at an entity (and maybe clicked on void),
    # then cancel.
    unless other && @agent.compatible?(other, in: @viewer)
      cancel

      raise EndHandlingEvent.new(event)
    end

    # If the user clicked at a *compatible* agent, make an edge with
    # that agent and cancel.
    @agent.connect(to: other, in: @viewer)

    cancel
  end
end

class MultiEdgeBuilder < EdgeBuilder
  def handle(event : SF::Event::MouseButtonPressed)
    other = @viewer.find_at_pixel?(Vector2.new(event.x, event.y))

    # If the user didn't click at an entity (and maybe clicked on void),
    # then cancel.
    unless other
      cancel
      return
    end

    # If the user clicked at an *incompatible* agent or another entity,
    # don't do anything, and ask the other handlers to skip the event.
    raise EndHandlingEvent.new(event) unless other.is_a?(Agent)
    raise EndHandlingEvent.new(event) unless @agent.compatible?(other, in: @viewer)

    # If the user clicked at a *compatible* agent, make an edge with
    # that agent and cancel.
    @agent.connect(to: other, in: @viewer)

    # Dismiss halos with the agent we've just connected to.
    @halos.reject! do |halo|
      if reject = halo.encloses?(other)
        halo.dismiss
      end

      reject
    end

    # Cancel if no more halos.
    if @halos.empty?
      cancel
      return
    end
  end
end

class EditorPanel
  include IDraggable
  include SF::Drawable

  getter editor : Editor

  @offset : Vector2

  def initialize(@editor : Editor)
    @offset = Vector2.new(@editor.size/2)
  end

  def lift(mouse : Vector2)
  end

  def drag(delta : Vector2, mouse : Vector2)
    @offset -= delta
  end

  def drop(mouse : Vector2)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    target.view.center = @offset.sfi
    target.draw(@editor)
  end
end

abstract class AgentEdge
  abstract def each_agent(& : Agent ->)

  def summon
    @viewer.insert(self)
  end

  def dismiss
    @viewer.delete(self)
  end

  def color
    SF::Color.new(0xaa, 0xaa, 0xaa)
  end
end

class AgentPointEdge < AgentEdge
  property point : Vector2

  def initialize(@viewer : AgentViewer, @agent : Agent, @point)
  end

  def each_agent(& : Agent ->)
    yield @agent
  end

  def append(*, to array)
    array.append(SF::Vertex.new(@agent.mid.sf, color))
    array.append(SF::Vertex.new(@point.sf, color))
  end

  def color
    SF::Color.new(0x43, 0x51, 0x80)
  end
end

class AgentAgentEdge < AgentEdge
  @spring : CP::Constraint

  def initialize(@viewer : AgentViewer, @left : Agent, @right : Agent)
    @spring = @left.spring to: @right, length: 100, stiffness: 100, damping: 50
  end

  def each_agent(& : Agent ->)
    yield @left
    yield @right
  end

  def contains?(*vertices : Agent)
    each_agent do |agent|
      return false unless agent.in?(vertices)
    end

    true
  end

  def summon
    super

    @viewer.@protoplasm.insert(@spring)
  end

  def dismiss
    super

    @viewer.@protoplasm.remove(@spring)
  end

  def append(*, to array)
    array.append(SF::Vertex.new(@left.mid.sf, color))
    array.append(SF::Vertex.new(@right.mid.sf, color))
  end

  def_equals_and_hash @left, @right
end

class AgentViewer
  include IDraggable

  # Returns the size of this viewer in pixels.
  getter size : Vector2

  def initialize(@size : Vector2)
    # Allocate 40% of width to the right-hand side editor panel, and
    # leave the rest to the protoplasm.
    @screen = SF::RenderTexture.new(size.x.to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @canvas = SF::RenderTexture.new((size.x * 0.6).to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @rpanel = SF::RenderTexture.new((size.x * 0.4).to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))

    @protoplasm = Protoplasm.new

    kw = KeywordRuleAgent.new(@protoplasm)
    kw.mid = 400.at(200)
    kw.register(self)
    kw.summon

    br = BirthRuleAgent.new(@protoplasm)
    br.mid = 500.at(200)
    br.register(self)
    br.summon

    hb = HeartbeatRuleAgent.new(@protoplasm)
    hb.mid = 200.at(200)
    hb.register(self)
    hb.summon

    pa = ProtocolAgent.new(@protoplasm)
    pa.mid = 200.at(300)
    pa.register(self)
    pa.summon
  end

  def connect(protocol : ProtocolAgent, rule : RuleAgent)
    edge = AgentAgentEdge.new(self, protocol, rule)
    edge.summon
  end

  @edges = Set(AgentEdge).new
  @halos = Set(Halo).new

  def insert(edge : AgentEdge)
    @edges << edge
  end

  def insert(halo : Halo)
    @halos << halo
  end

  def has_edge?(left : ProtocolAgent, right : RuleAgent)
    @edges.any? { |edge| edge.is_a?(AgentAgentEdge) && edge.contains?(left, right) }
  end

  def delete(edge : AgentEdge)
    @edges.delete(edge)
  end

  def delete(halo : Halo)
    @halos.delete(halo)
  end

  @states = {} of UInt64 => EditorPanel
  @editor : EditorPanel?

  def register(editor : Editor)
    @states[editor.object_id] = EditorPanel.new(editor)
  end

  def unregister(editor : Editor)
    @states.delete(editor.object_id)
  end

  def registered!(editor : Editor)
    unless @states.has_key?(editor.object_id)
      raise "AgentViewer: cannot use an unregistered editor"
    end
  end

  def editor(&)
    @editor.try { |state| yield state.editor }
  end

  def editor_open?
    !!@editor
  end

  def editor_open?(editor : Editor)
    !!@editor.try { |state| state.editor.same?(editor) }
  end

  def open(opener : Agent, editor : Editor)
    registered!(editor)

    editor do |prev|
      next if prev.same?(editor)

      prev.blur

      # Gracefully close the previous editor if the new editor
      # is different.
      close(prev)
    end

    editor.focus

    @editor = @states[editor.object_id]
  end

  def close(editor : Editor)
    registered!(editor)

    puts "close #{editor}"
  end

  def edit(entity : Agent)
    entity.open(in: self)
  end

  def edit(entity : Nil)
    editor do |prev|
      prev.blur

      close(prev)

      @editor = nil
    end
  end

  def inspect(entity : Entity?, &)
    @protoplasm.inspect(entity) do
      edit(entity)

      yield
    end
  end

  def inspect(entity : Entity?)
    inspect(entity) { }
  end

  delegate :each_agent, to: @protoplasm

  def protoplasm_at_pixel?(pixel : Vector2)
    pixel.x.in?(0...@canvas.size.x) && pixel.y.in?(0...@canvas.size.y)
  end

  def pixel_to_protoplasm(pixel : Vector2)
    Vector2.new @canvas.map_pixel_to_coords(pixel.sfi)
  end

  def pixel_to_protoplasm?(pixel : Vector2)
    return unless protoplasm_at_pixel?(pixel)

    Vector2.new @canvas.map_pixel_to_coords(pixel.sfi)
  end

  def find_at_pixel?(pixel : Vector2)
    return unless protoplasm_at_pixel?(pixel)

    coords = Vector2.new @canvas.map_pixel_to_coords(pixel.sfi)

    @protoplasm.find_at?(coords)
  end

  def find_at_pixel?(pixel : Vector2, entity : T.class) forall T
    return unless protoplasm_at_pixel?(pixel)

    coords = Vector2.new @canvas.map_pixel_to_coords(pixel.sfi)

    @protoplasm.find_at?(coords, entity)
  end

  def editor_at_pixel?(pixel : Vector2, &)
    return unless state = @editor

    editor = state.editor
    coords = Vector2.new @rpanel.map_pixel_to_coords((pixel - @canvas.size.x.x).sfi)

    if editor.includes?(coords.sf)
      yield editor
    end
  end

  def register(handlers : EventHandlerStore)
    handlers.register(AgentViewerDispatcher.new(handlers, self))
    handlers.register(EdgeCreator.new(handlers, self))
  end

  @draggable : IDraggable?

  def lift(mouse : Vector2)
    @draggable = protoplasm_at_pixel?(mouse) ? self : @editor
  end

  def drag(delta : Vector2, mouse : Vector2)
    draggable = @draggable
    draggable ||= @editor unless protoplasm_at_pixel?(mouse)
    draggable ||= self

    #
    # If there is an explicit draggable and it's not self, redirect
    # drag to it. Otherwise, use canvas as the surface.
    #
    unless same?(draggable)
      draggable.drag(delta, mouse)
      return
    end

    view = @canvas.view
    view.move(-delta.sfi)
    @canvas.view = view
  end

  def drop(mouse : Vector2)
    @draggable = nil
  end

  def tick(delta : Float)
    @protoplasm.tick(delta)
  end

  # Specifies the background color of this editor.
  def background_color
    SF::Color.new(0x31, 0x31, 0x31)
  end

  # Refreshes the underlying texture.
  private def refresh
    @canvas.clear(background_color)
    edges = SF::VertexArray.new(SF::Lines)
    @edges.each do |edge|
      edge.append(to: edges)
    end
    @canvas.draw(edges)
    @protoplasm.draw(:entities, @canvas)
    @canvas.display

    @rpanel.clear(SF::Color.new(0x37, 0x37, 0x37))
    if state = @editor
      @rpanel.draw(state)
    else
      @rpanel.view = @rpanel.default_view
      rpanel_hint = SF::Text.new("Hint: click on an agent to edit", FONT_ITALIC, 11)
      rpanel_hint.color = SF::Color.new(0x99, 0x99, 0x99)
      rpanel_hint.position = ((@rpanel.size - rpanel_hint.size) / 2).to_i
      @rpanel.draw(rpanel_hint)
    end
    @rpanel.display

    @screen.clear(background_color)

    #
    # Draw canvas sprite.
    #
    canvas = SF::Sprite.new(@canvas.texture)
    @screen.draw(canvas)

    #
    # Draw right-hand side editor panel.
    #
    rpanel = SF::Sprite.new(@rpanel.texture)
    rpanel.position += SF.vector2f(@canvas.size.x, 0)
    @screen.draw(rpanel)

    #
    # Draw right-hand side panel splitter.
    #
    rpanel_splitter = SF::RectangleShape.new
    rpanel_splitter.size = SF.vector2f(2, @canvas.size.y / 2)
    rpanel_splitter.position = rpanel.position + SF.vector2f(4, @canvas.size.y/4)
    rpanel_splitter.fill_color = @protoplasm.inspecting?(nil) ? SF::Color.new(0x45, 0x45, 0x45) : SF::Color.new(0x43, 0x51, 0x80)

    @screen.draw(rpanel_splitter)

    @screen.display
  end

  # Refreshes this editor, and yields an SFML Sprite object so that the
  # caller can position and draw it where desired.
  def draw(& : SF::Sprite ->)
    refresh

    yield SF::Sprite.new(@screen.texture)
  end
end

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "Hello World", settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
window.framerate_limit = 60

handlers = EventHandlerStore.new

viewer = AgentViewer.new(700.at(400))
viewer.register(handlers)

# TODO:
#

clicks = 0
mouseup = nil
mousedown = nil
mousedown_at = nil

tt = TimeTable.new(ClockAuthority.new)

click_timeout = nil

released_queue = nil

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::MouseButtonPressed
      clicks += 1
      mousedown = event

      click_timeout ||= tt.after(150.milliseconds) do
        mousedown.try do |event|
          event.clicks = clicks
          handlers.handle(event)
        end
        mouseup.try { |event| handlers.handle(event) }
        clicks = 0
        click_timeout = nil
        mouseup = nil
        mousedown = nil
      end

      next
    when SF::Event::MouseButtonReleased
      if mousedown
        mouseup = event
        next
      end
    when SF::Event::MouseMoved
      if (md = mousedown) && (event.x - md.x)**2 + (event.y - md.y)**2 > 16 # > 4px
        mousedown.try do |event|
          event.clicks = clicks
          handlers.handle(event)
        end
        mouseup.try { |event| handlers.handle(event) }
        clicks = 0
        tt.cancel(click_timeout.not_nil!)
        click_timeout = nil
        mouseup = nil
        mousedown = nil
        next
      end
    end

    handlers.handle(event)
  end

  tt.tick

  viewer.tick(1/60)

  window.clear(SF::Color::White)
  viewer.draw do |sprite|
    window.draw(sprite)
  end
  window.display
end
