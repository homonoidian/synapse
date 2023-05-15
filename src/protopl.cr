require "colorize"

require "crsfml"
require "chipmunk"
require "chipmunk/chipmunk_crsfml"
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
require "./synapse/ui/label"
require "./synapse/ui/menu_item"
require "./synapse/ui/menu"
require "./synapse/ui/*"

require "./ped2"

require "./synapse/system/protoplasm/agent_graph"

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

  def inspect_prev_agent(*, in viewer : AgentViewer)
    @lens.each do |agent|
      next unless agent.is_a?(Agent)

      if pred = agent.pred?(in: viewer)
        inspect pred
      end

      break
    end
  end

  def inspect_next_agent(*, in viewer : AgentViewer)
    @lens.each do |agent|
      next unless agent.is_a?(Agent)

      if succ = agent.succ?(in: viewer)
        inspect(succ)
      end

      break
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
  private getter! errors : ErrorMessageViewer # fix this somehow

  def initialize(tank : Tank)
    super(tank, self.class.color, lifespan: nil)

    @editor = to_editor
    @dragged = false

    @errors = ErrorMessageViewer.new(self)
  end

  protected abstract def to_editor : Editor

  def pred?(*, in viewer : AgentViewer)
  end

  def succ?(*, in viewer : AgentViewer)
  end

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
      SF::Color.new(0x58, 0x65, 0x96)
    else
      _, c, h = LCH.rgb2lch(icon_color.r, icon_color.g, icon_color.b)

      SF::Color.new(*LCH.lch2rgb(40, 10, h))
    end
  end

  @paused = false

  def play
    @paused = false
  end

  def pause
    @paused = true
  end

  def failed?
    errors.any?
  end

  def to_next_error
    errors.to_next
  end

  def to_prev_error
    errors.to_prev
  end

  def fail(message : String)
    errors.insert(ErrorMessage.new(message))

    halo = Halo.new(self, SF::Color.new(0xE5, 0x73, 0x73, 0x33), overlay: false)
    halo.summon
  end

  def lift(mouse : Vector2)
    @dragged = true
  end

  def drag(delta : Vector2, mouse : Vector2)
    # We don't use delta because physics influences our position
    # too, so we want to be authoritative.
    self.mid = mouse
  end

  def drop(mouse : Vector2)
    @dragged = false
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

  def slide_joint(*, with other : Agent, **kwargs)
    other.slide_joint(@body, **kwargs)
  end

  def spring(body : CP::Body, length : Number, stiffness : Number, damping : Number)
    CP::Constraint::DampedSpring.new(@body, body, CP.v(0, 0), CP.v(0, 0), length, stiffness, damping)
  end

  def slide_joint(body : CP::Body, min : Number, max : Number)
    CP::Constraint::SlideJoint.new(@body, body, CP.v(0, 0), CP.v(0, 0), min, max)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    if @dragged
      shadow = SF::CircleShape.new
      shadow.radius = self.class.radius * 1.1
      shadow.position = (mid - shadow.radius + 0.at(10)).sf
      shadow.fill_color = SF::Color.new(0, 0, 0, 0x33)
      shadow.draw(target, states)
    end

    each_halo_with_drawable { |_, drawable| target.draw(drawable) }

    circle = SF::CircleShape.new
    circle.radius = self.class.radius
    circle.position = (mid - self.class.radius.xy).sfi
    circle.fill_color = @color
    circle.outline_thickness = @tank.inspecting?(self) ? 3 : 1
    circle.outline_color = outline_color
    circle.draw(target, states)

    icon = icon_text
    if @paused
      icon.string = Icon::Paused
      icon.character_size = 18
    end
    icon.position = circle.position.to_i + ((circle.radius.xy - Vector2.new(icon.size)/2) - 1.y).sfi
    icon.draw(target, states)

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

    if @paused
      dark_overlay = SF::CircleShape.new
      dark_overlay.radius = circle.radius
      dark_overlay.position = circle.position
      dark_overlay.fill_color = SF::Color.new(0, 0, 0, 0xaa)
      target.draw(dark_overlay)
    end

    target.draw(errors)
  end

  # Fills the editor of this agent with the captured content of the
  # *other* editor.
  def drain(other : Editor)
  end

  # Defines the drain method for the given editor *type* stored in
  # `@editor` at runtime.
  macro def_drain_as(type)
    # Fills the editor of this agent with the captured content of
    # the given `{{type}}`.
    def drain(editor : {{type}})
      @editor.as({{type}}).drain(editor)
    end
  end

  abstract def replicate(*, in viewer : AgentViewer)
end

class ProtocolAgent < Agent
  def_drain_as ProtocolEditor

  def replicate(*, in viewer : AgentViewer)
    protocol = viewer.summon(ProtocolAgent, at: mid)
    protocol.drain(@editor)

    viewer.each_rule(of: self) do |rule|
      rule.replicate(under: protocol, in: viewer)
    end

    protocol
  end

  def title?
    @editor.title? || "Untitled"
  end

  def succ?(*, in viewer : AgentViewer)
    candidate = nil
    distance = nil

    @tank.each_entity(ProtocolAgent) do |agent|
      next unless agent.mid.x > mid.x || ((agent.mid.x - mid.x).abs < 8 && agent.mid.y > mid.y)
      if distance.nil? || (agent.mid - mid).magn < distance
        candidate = agent
      end
    end

    candidate
  end

  def pred?(*, in viewer : AgentViewer)
    candidate = nil
    distance = nil

    @tank.each_entity(ProtocolAgent) do |agent|
      next unless agent.mid.x < mid.x || ((agent.mid.x - mid.x).abs < 8 && agent.mid.y < mid.y)
      if distance.nil? || (agent.mid - mid).magn < distance
        candidate = agent
      end
    end

    candidate
  end

  def pred?(of agent : RuleAgent, in viewer : AgentViewer)
    distance = nil
    candidate = nil
    viewer.each_rule(of: self) do |rule|
      next unless rule.mid.x < agent.mid.x || ((rule.mid.x - agent.mid.x).abs < 8 && rule.mid.y < agent.mid.y)
      if distance.nil? || (rule.mid - agent.mid).magn < distance
        candidate = rule
      end
    end
    candidate
  end

  def succ?(of agent : RuleAgent, in viewer : AgentViewer)
    distance = nil
    candidate = nil
    viewer.each_rule(of: self) do |rule|
      next unless rule.mid.x > agent.mid.x || ((rule.mid.x - agent.mid.x).abs < 8 && rule.mid.y > agent.mid.y)
      return rule
    end
    candidate
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
    !viewer.connected?(self, other)
  end

  def connect(*, to other : RuleAgent, in viewer : AgentViewer)
    viewer.connect(self, other)
  end
end

abstract class RuleAgent < Agent
  def replicate(*, in viewer : AgentViewer)
    copy = viewer.summon(self.class, at: mid)
    copy.drain(@editor)
    copy
  end

  def replicate(*, under protocol : ProtocolAgent, in viewer : AgentViewer)
    copy = replicate(in: viewer)
    copy.connect(to: protocol, in: viewer)
    copy
  end

  def succ?(*, in viewer : AgentViewer)
    candidate = nil
    distance = nil

    viewer.each_protocol(of: self) do |protocol|
      next unless succ = protocol.succ?(of: self, in: viewer)

      if distance.nil? || (succ.mid - mid).magn < distance
        candidate = succ
      end
    end

    candidate
  end

  def pred?(*, in viewer : AgentViewer)
    candidate = nil
    distance = nil

    viewer.each_protocol(of: self) do |protocol|
      next unless pred = protocol.pred?(of: self, in: viewer)

      if distance.nil? || (pred.mid - mid).magn < distance
        candidate = pred
      end
    end

    candidate
  end

  def compatible?(other : ProtocolAgent, in viewer : AgentViewer)
    other.compatible?(self, in: viewer)
  end

  def connect(*, to other : ProtocolAgent, in viewer : AgentViewer)
    viewer.connect(other, self)
  end
end

class HeartbeatRuleAgent < RuleAgent
  delegate :title?, to: @editor

  def_drain_as HeartbeatRuleEditor

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

  def_drain_as BirthRuleEditor

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

  def_drain_as KeywordRuleEditor

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

  def initialize(@recipient : IHaloSupport, @color : SF::Color, *, @overlay = false)
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

  def_equals_and_hash @recipient, @color, @overlay
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

class AgentSummoner < EventHandler
  @agent : Agent

  def initialize(handlers : EventHandlerStore, @viewer : AgentViewer, agent : Agent.class, pixel : Vector2)
    super(handlers)

    @agent = @viewer.summon(agent, at: pixel)
    @agent.lift(pixel)
    @viewer.inspect(@agent)
  end

  def major?
    true
  end

  def place
    @agent.drop(@agent.mid)
    @handlers.unregister(self)
  end

  def cancel
    @agent.drop(@agent.mid)
    @viewer.dismiss(@agent)
    @handlers.unregister(self)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    place
  end

  def handle(event : SF::Event::MouseMoved)
    coords = @viewer.pixel_to_protoplasm(event.x.at(event.y))

    @agent.drag(@agent.mid - coords, coords)
  end

  def handle(event : SF::Event::KeyPressed)
    case event.code
    when .escape?, .delete?, .backspace?, .enter?
      cancel
    end
  end

  def handle(event : SF::Event::TextEntered)
    place

    @viewer.inspect(@agent)
  end
end

class AgentDismisser < EventHandler
  def initialize(handlers : EventHandlerStore, @viewer : AgentViewer)
    super(handlers)

    @cursor = SF::Cursor.from_system(SF::Cursor::Type::Cross)
    @viewer.push_cursor(@cursor)
  end

  def dismiss
    @viewer.pop_cursor(@cursor)
    @handlers.unregister(self)
  end

  def major?
    true
  end

  def handle(event : SF::Event::MouseButtonPressed)
    unless event.clicks == 1 && event.button.left?
      dismiss
      return
    end

    coords = event.x.at(event.y)

    if agent = @viewer.find_at_pixel?(coords, entity: Agent)
      @viewer.dismiss(agent)
    end

    dismiss

    raise EndHandlingEvent.new(event)
  end

  def handle(event : SF::Event::KeyPressed)
    case event.code
    when .escape?, .backspace?, .delete?, .enter?
      dismiss
      raise EndHandlingEvent.new(event)
    else
    end
  end

  def handle(event : SF::Event)
    raise EndHandlingEvent.new(event)
  end
end

class SummonMenuDispatcher < EventHandler
  def initialize(handlers : EventHandlerStore, @viewer : AgentViewer, pixel : Vector2, @parent : ProtocolAgent? = nil)
    super(handlers)

    #
    # Create a menu object that will be used to display summon options.
    #
    @menu = Menu.new(MenuState.new, MenuView.new)
    @menu.accepted { |instant| accept(instant.caption) }

    #
    # Fill it with the summon options.
    #
    fill(@menu)

    #
    # Insert it into the viewer so that the viewer can draw it.
    #
    @viewer.register(@menu)

    #
    # Open the menu.
    #
    @menu.open(pixel.x + 1, pixel.y + 1)
  end

  # Fills the given *menu* object with summon options.
  def fill(menu : Menu)
    menu.append("New birth rule", Icon::BirthRule)
    menu.append("New keyword rule", Icon::KeywordRule)
    menu.append("New heartbeat rule", Icon::HeartbeatRule)

    # Do not show "New protocol" if there's a parent: this won't make
    # a lot of sense since protocols can't be parents of protocols.
    unless @parent
      menu.append("New protocol", Icon::Protocol)
    end
  end

  def major?
    true
  end

  def summon(cls : RuleAgent.class, at pixel : Vector2)
    if protocol = @parent.as?(ProtocolAgent)
      agent = @viewer.summon(cls, at: pixel)
      @viewer.inspect(agent)
      protocol.connect(to: agent, in: @viewer)
    else
      @handlers.register AgentSummoner.new(@handlers, @viewer, agent: cls, pixel: pixel)
    end
  end

  def summon(cls : Agent.class, at pixel : Vector2)
    @handlers.register AgentSummoner.new(@handlers, @viewer, agent: cls, pixel: pixel)
  end

  # Accepts the given menu *option*: registers the appropriate
  # `AgentSummoner` and closes the menu.
  def accept(option : String)
    cls = {
      "New birth rule":     BirthRuleAgent,
      "New keyword rule":   KeywordRuleAgent,
      "New heartbeat rule": HeartbeatRuleAgent,
      "New protocol":       ProtocolAgent,
    }[option]

    summon(cls, at: @viewer.mouse)

    cancel
  end

  # Closes the menu and unregisters self.
  def cancel
    @menu.close
    @handlers.unregister(self)
  end

  # Forwards the given *event* to the menu.
  def forward(event : SF::Event)
    @menu.handle(event)

    raise EndHandlingEvent.new(event)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    unless event.button.left?
      cancel
      return
    end

    coords = Vector2.new(event.x, event.y)

    unless @menu.includes?(coords.sf)
      cancel
      return
    end

    forward(event)
  end

  def handle(event : SF::Event)
    forward(event)
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
      editor.focus
      # TODO: make editors IDraggable instead of having another Draggable module
      editor.handle(event)
      return
    end

    protoplasm = @viewer.protoplasm_at_pixel?(coords)

    unless protoplasm && @viewer.editor_open?
      @viewer.editor &.blur
    end

    # Open menu at the right-hand side.
    if protoplasm && event.button.right?
      @handlers.register(SummonMenuDispatcher.new(@handlers, @viewer, pixel: coords))
      return
    end

    if agent = @viewer.find_at_pixel?(coords, entity: Agent)
      if @ctrl
        agent = agent.replicate(in: @viewer)
      end

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
    if protoplasm
      @viewer.inspect(nil)
    end

    @handlers.register DragHandler.new(@handlers, @viewer, coords, oneshot: true)
  end

  def forward(event : SF::Event)
    return unless @viewer.editor_open?

    @viewer.editor &.handle(event)
  end

  @shift = false
  @ctrl = false

  def handle(event : SF::Event::KeyPressed)
    @shift = event.shift || event.code.l_shift? || event.code.r_shift?
    @ctrl = event.control || event.code.l_control? || event.code.r_control?

    case event.code
    when .escape?
      if @viewer.editor_open?
        @viewer.editor &.blur
        return
      end
    when .delete?
      unless @viewer.editor_open?
        @handlers.register AgentDismisser.new(@handlers, @viewer)
      end
    when .tab?
      if @ctrl
        @shift ? @viewer.to_prev_agent : @viewer.to_next_agent
        return
      end
    end

    forward(event)
  end

  def handle(event : SF::Event::KeyReleased)
    @shift = false if event.code.l_shift? || event.code.r_shift?
    @ctrl = false if event.code.l_control? || event.code.r_control?

    forward(event)
  end

  def handle(event : SF::Event::MouseWheelScrolled)
    coords = event.x.at(event.y)
    agent = @viewer.find_at_pixel?(coords, entity: Agent)
    if agent && agent.failed?
      event.delta.negative? ? agent.to_next_error : agent.to_prev_error
    else
      @viewer.drag((@shift ? event.delta.x : event.delta.y) * 10, event.x.at(event.y))
    end
  end

  def handle(event : SF::Event)
    forward(event)
  end
end

class EdgeCreator < EventHandler
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
  @edge : AgentPointEdge

  def initialize(handlers : EventHandlerStore, @viewer : AgentViewer, @agent : Agent)
    super(handlers)

    @edge = @viewer.connect(@agent, @agent.mid)
    @halos = [] of Halo

    #
    # Find agents that self is compatible with, and add a halo to
    # them so that the user can see where they can connect.
    #
    @viewer.each_agent do |other|
      next if @agent.same?(other)
      next unless @agent.compatible?(other, in: @viewer)

      halo = Halo.new(other, SF::Color.new(0x43, 0x51, 0x80, 0x55), overlay: true)
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

      raise EndHandlingEvent.new(event)
    end
  end
end

class SingleEdgeBuilder < EdgeBuilder
  def handle(event : SF::Event::MouseButtonReleased)
    coords = Vector2.new(event.x, event.y)
    other = @viewer.find_at_pixel?(coords, entity: Agent)

    # If the user didn't click at an entity (and maybe clicked on void),
    # give them the summon menu.
    unless other
      cancel

      if protocol = @agent.as?(ProtocolAgent)
        @handlers.register(SummonMenuDispatcher.new(@handlers, @viewer, coords, parent: protocol))
      end

      raise EndHandlingEvent.new(event)
    end

    # Cancel if over an agent but not compatible.
    unless @agent.compatible?(other, in: @viewer)
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
    coords = Vector2.new(event.x, event.y)
    other = @viewer.find_at_pixel?(coords)

    # If the user didn't click at an entity (and maybe clicked on void),
    # give them the summon menu.
    unless other
      cancel

      if protocol = @agent.as?(ProtocolAgent)
        @handlers.register(SummonMenuDispatcher.new(@handlers, @viewer, coords, parent: protocol))
      end

      raise EndHandlingEvent.new(event)
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

  def initialize(@viewer : AgentViewer, @editor : Editor)
    @offset = Vector2.new(@editor.size/2) + (viewer.size.y / 4).y
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
  def initialize(@graph : AgentGraph)
  end

  abstract def each_agent(& : Agent ->)

  def find?(needle : T.class) : T? forall T
    each_agent do |agent|
      next unless agent.is_a?(T)
      return agent
    end
  end

  def contains?(vertex : Agent)
    each_agent do |agent|
      return true if vertex == agent
    end

    false
  end

  def contains?(*vertices : Agent)
    vertices.all? { |vertex| contains?(vertex) }
  end

  def constrain(tank : Tank)
  end

  def loosen(tank : Tank)
  end

  def summon
    @graph.insert(self)
  end

  def dismiss
    @graph.remove(self)
  end

  def color
    SF::Color.new(0x77, 0x77, 0x77)
  end
end

class AgentPointEdge < AgentEdge
  property point : Vector2

  def initialize(graph : AgentGraph, @agent : Agent, @point)
    super(graph)
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

abstract class AgentAgentConstraint < AgentEdge
  @constraint : CP::Constraint

  def initialize(graph : AgentGraph, @a : Agent, @b : Agent)
    super(graph)

    @constraint = constraint
  end

  abstract def constraint : CP::Constraint

  def constrain(tank : Tank)
    tank.insert(@constraint)
  end

  def loosen(tank : Tank)
    tank.remove(@constraint)
  end

  def each_agent(& : Agent ->)
    yield @a
    yield @b
  end

  def visible?
    true
  end

  def append(*, to array)
    return unless visible?

    array.append(SF::Vertex.new(@a.mid.sf, color))
    array.append(SF::Vertex.new(@b.mid.sf, color))
  end

  def_equals_and_hash @a, @b
end

class AgentAgentEdge < AgentAgentConstraint
  def constraint : CP::Constraint
    @a.spring to: @b,
      length: self.class.length,
      stiffness: self.class.stiffness,
      damping: self.class.damping
  end

  def self.length
    100
  end

  def self.stiffness
    150
  end

  def self.damping
    150
  end
end

class KeepcloseLink < AgentAgentEdge
  def self.length
    3 * Agent.radius
  end

  def self.stiffness
    100
  end

  def self.damping
    200
  end

  def visible?
    false
  end
end

class KeepawayLink < AgentAgentConstraint
  def constraint : CP::Constraint
    @a.slide_joint with: @b, min: self.class.min, max: self.class.max
  end

  def self.min
    4 * Agent.radius
  end

  def self.max
    10 * Agent.radius
  end

  def visible?
    false
  end
end

class ErrorMessage
  def initialize(@message : String)
    @text = SF::Text.new(@message, FONT_BOLD, 11)
  end

  def size
    @text.size
  end

  def put(*, on target : SF::RenderTarget, at point : Vector2)
    @text.position = point.sfi
    @text.fill_color = SF::Color.new(0xB7, 0x1C, 0x1C)
    target.draw(@text)
  end
end

class ErrorMessageViewer
  include SF::Drawable

  def initialize(@agent : Agent)
    @errors = [] of ErrorMessage
    @current = 0
  end

  def any?
    !@errors.empty?
  end

  def at_first?
    @current == 0
  end

  def at_last?
    @current == @errors.size - 1
  end

  def to_prev
    return if at_first?

    @current -= 1
  end

  def to_next
    return if at_last?

    @current += 1
  end

  def insert(error : ErrorMessage)
    @errors << error
    @current = @errors.size - 1
  end

  def delete(error : ErrorMessage)
    @errors.delete(error)
    @current = @errors.size - 1
  end

  def padding
    5.at(3)
  end

  def draw(target, states)
    error = @errors[@current]? || return

    extent = Vector2.new(error.size) + padding*2
    origin = @agent.mid - extent.y + @agent.class.radius.xy * 1.5.at(-1.5)

    bg = SF::RectangleShape.new
    bg.position = origin.sfi
    bg.size = extent.sfi
    bg.fill_color = SF::Color.new(0xEF, 0x9A, 0x9A, 0xdd)

    src = @agent.mid - @agent.class.radius.y
    dst = origin + extent.y.y
    dir = dst - src

    connector = SF::RectangleShape.new
    connector.size = SF.vector2f(dir.magn, 2)
    connector.position = src.sf
    connector.rotate(Math.degrees(Math.atan2(dir.y, dir.x)))
    connector.fill_color = SF::Color.new(0xEF, 0x9A, 0x9A)

    connector_tip = SF::CircleShape.new
    connector_tip.radius = 3
    connector_tip.position = (src - connector_tip.radius).sf
    connector_tip.fill_color = SF::Color.new(0xEF, 0x9A, 0x9A)

    target.draw(connector)
    target.draw(connector_tip)

    target.draw(bg)
    error.put(on: target, at: origin + padding)

    return if @errors.size < 2

    scrollbar = SF::RectangleShape.new
    scrollbar.fill_color = SF::Color.new(0x51, 0x51, 0x51)
    scrollbar.size = SF.vector2f(bg.size.x + bg.outline_thickness*2, 6)
    scrollbar.position = SF.vector2f(bg.position.x - bg.outline_thickness, bg.position.y - scrollbar.size.y - 3)

    # Compute width of the scrollhead
    scrollhead_lo = 4
    scrollhead_hi = scrollbar.size.x - scrollhead_lo

    scrollhead_width = (scrollhead_hi - scrollhead_lo) / @errors.size
    scrollhead_offset = @current * scrollhead_width + scrollhead_lo

    scrollhead = SF::RectangleShape.new
    scrollhead.fill_color = SF::Color.new(0x71, 0x71, 0x71)
    scrollhead.size = SF.vector2f(scrollhead_width, 3)
    scrollhead.position = scrollbar.position + SF.vector2(scrollhead_offset, (scrollbar.size.y - scrollhead.size.y)/2)

    target.draw(scrollbar)
    target.draw(scrollhead)
  end
end

class AgentViewer
  include IDraggable

  # Returns the size of this viewer in pixels.
  getter size : Vector2

  def initialize(@window : SF::RenderWindow, @mouse : BoxedVector2, @size : Vector2)
    # Allocate 40% of width to the right-hand side editor panel, and
    # leave the rest to the protoplasm.
    @screen = SF::RenderTexture.new(size.x.to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @canvas = SF::RenderTexture.new((size.x * 0.6).to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @rpanel = SF::RenderTexture.new((size.x * 0.4).to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))

    @protoplasm = Protoplasm.new
    @graph = AgentGraph.new(@protoplasm)

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

  delegate :connect, :disconnect, :connected?, :each_protocol, :each_rule, to: @graph

  @cursors = [] of SF::Cursor

  def push_cursor(cursor : SF::Cursor)
    @cursors << cursor
    @window.mouse_cursor = cursor
  end

  def pop_cursor(cursor : SF::Cursor)
    @cursors.delete_at(@cursors.rindex(cursor) || raise "cursor was not pushed: #{cursor}")
    @window.mouse_cursor = @cursors.last? || SF::Cursor.from_system(SF::Cursor::Type::Arrow)
  end

  def summon(cls : Agent.class, *, at pixel : Vector2)
    agent = cls.new(@protoplasm)
    agent.mid = pixel_to_protoplasm(pixel)
    agent.register(self)
    agent.summon
    agent
  end

  def dismiss(agent : Agent)
    edit(entity: nil)

    agent.unregister(self)

    @graph.disconnect(agent)

    agent.dismiss
  end

  def to_prev_agent
    @protoplasm.inspect_prev_agent(in: self)
  end

  def to_next_agent
    @protoplasm.inspect_next_agent(in: self)
  end

  @states = {} of UInt64 => EditorPanel
  @editor : EditorPanel?
  @menu : Menu?

  def register(editor : Editor)
    @states[editor.object_id] = EditorPanel.new(self, editor)
  end

  def register(menu : Menu)
    @menu.try &.close
    @menu = menu
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

  def editor_focused?
    editor { |editor| return editor.focused? }

    false
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

  def mouse
    @mouse.unbox
  end

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
    @graph.each_edge &.append(to: edges)
    @canvas.draw(edges)
    @protoplasm.draw(:entities, @canvas)
    # dd = SFMLDebugDraw.new(@canvas)
    # dd.draw(@protoplasm.@space)

    @canvas.display

    @rpanel.clear(SF::Color.new(0x37, 0x37, 0x37))
    if state = @editor
      @rpanel.draw(state)
    else
      @rpanel.view = @rpanel.default_view
      rpanel_hint = SF::Text.new("Hint: click on an agent to edit. Right-click to\ncreate an agent.", FONT_ITALIC, 11)
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

    @menu.try { |menu| @screen.draw(menu) }

    @screen.display
  end

  # Refreshes this editor, and yields an SFML Sprite object so that the
  # caller can position and draw it where desired.
  def draw(& : SF::Sprite ->)
    refresh

    yield SF::Sprite.new(@screen.texture)
  end
end

class BoxedVector2
  def initialize(@vector : Vector2)
  end

  def set(@vector)
  end

  def unbox
    @vector
  end
end

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "Hello World", settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
window.framerate_limit = 60

handlers = EventHandlerStore.new

mouse = BoxedVector2.new(0.at(0))

viewer = AgentViewer.new(window, mouse, 700.at(400))
viewer.register(handlers)
a = viewer.@protoplasm.@entities.sample(Agent)
a.pause
a.fail("This is an example of an error message")
b = viewer.@protoplasm.@entities.sample(Agent)
b.pause
b.fail("This is an example of another error message #1")
b.fail("This is an example of another error message #2")
b.fail("This is an example of another error message #3")
b.fail("This is an example of another error message #4")
b.fail("This is an example of another error message #5")
b.fail("This is an example of another error message #6")

# TODO:
#
# [x] connect agents with struts
# [x] port right-click menu
# [x] implement error overlay & halo for one or more errors
# [x] when an agent is paused (a boolean flag), it's darkened and a "paused"
#     icon appears on it
# [x] implement deletion of agents/protocols
# [x] implement C-Tab/C-S-Tab
# [x] implement ctrl-drag to copy rule within protocol and ctrl-drag to
#     copy entire protocol
# [ ] bridge with protocols & rules: be able to initialize a agentviewer
#     from a protocolcollection & keep it there, agents own rules/protocols?
# [ ] when agentviewer receives message, it forwards to matching protocol?
# [ ] when protocol receives message, it forwards to matching agent?
# [ ] when agent receives message, it executes matching rule?
# [ ] heartbeatagent triggers its rule on tick?
# [ ] rename 'agent' to 'actor' everywhere: my typo propagated...?
# [ ] refactor into an isolated, connectable component & document
#   [ ] split agent viewer into... something.. s? it's too big and does
#       too much. also eventhandler and eventhandlerstore are bad names
#       for what they do / what is done with them -- they have much more
#       agency than simple event handlers
# [ ] merge with the main editor
# [ ] implement play/pause for protocols which is triggered by Protocol#enable/
#     Protocol#disable/etc. Pausing a protocol pauses all rules
# [ ] implement play/pause for protoplasm (that is, for Tank)
# [ ] use play/pause on tank as an implementation of play/pause instead
#     of the weird ClockAuthority stuff -- implement TimeTable#pause and
#     TimeTable#unpause.
# [ ] add a GUI way to pause/unpause individual cells
# [ ] add a GUI way to pause/unpause individual rules
# [ ] add a GUI way to pause/unpause individual protocols

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
    when SF::Event::MouseWheelScrolled
      mouse.set(event.x.at(event.y))
    when SF::Event::GainedFocus
      pos = SF::Mouse.get_position(window)
      mouse.set(Vector2.new(pos))
    when SF::Event::MouseButtonPressed
      mouse.set(event.x.at(event.y))

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
      mouse.set(event.x.at(event.y))

      if mousedown
        mouseup = event
        next
      end
    when SF::Event::MouseMoved
      mouse.set(event.x.at(event.y))

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
