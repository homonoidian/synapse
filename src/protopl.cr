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

require "./synapse/system/protoplasm/edge"
require "./synapse/system/protoplasm/agent"
require "./synapse/system/protoplasm/protocol_agent"
require "./synapse/system/protoplasm/rule_agent"
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

class EventAuthorityRegistry
  def initialize
    @registered = [] of EventAuthority
  end

  def register(authority : EventAuthority)
    if authority.major?
      # Put major handlers in front. Major handlers usually throw
      # the EndHandling exception to signal that event handling
      # should stop.
      @registered.unshift(authority)
    else
      @registered.push(authority)
    end
  end

  def unregister(authority : EventAuthority)
    @registered.delete(authority)
  end

  def clear
    @registered.clear
  end

  def dispatch(event : SF::Event)
    active = @registered.dup
    active.each &.handle(event)
  rescue e : EndHandlingEvent
    raise e unless e.event == event
  end
end

abstract class EventAuthority
  def initialize(@registry : EventAuthorityRegistry)
  end

  def major?
    false
  end

  def handle(event : SF::Event)
  end
end

class DragHandler < EventAuthority
  @grip : Vector2

  def initialize(registry : EventAuthorityRegistry, @item : IDraggable, grip : Vector2, @oneshot = false)
    super(registry)

    @grip = map(grip)
    @item.lifted
  end

  def map(pixel : Vector2)
    pixel
  end

  # Sends `drop` message to the item.
  def handle(event : SF::Event::MouseButtonReleased)
    @item.dropped
    @registry.unregister(self) if @oneshot # oneshot is evhcollection responsibility!
  end

  # Sends `drag` message to the item if the item is being dragged.
  def handle(event : SF::Event::MouseMoved)
    return unless grip = @grip

    coords = map(event.x.at(event.y))

    @item.dragged(coords - grip)
    @grip = coords
  end
end

class AgentDragHandler < DragHandler
  def initialize(@browser : AgentBrowser, *args, **kwargs)
    super(*args, **kwargs)
  end

  def map(pixel : Vector2)
    @browser.pixel_to_protoplasm(pixel)
  end
end

class AgentSummoner < EventAuthority
  @agent : Agent

  def initialize(registry : EventAuthorityRegistry, @browser : AgentBrowser, agent : Agent.class, pixel : Vector2)
    super(registry)

    @agent = @browser.summon(agent, pixel: pixel)
    @agent.lifted
    @browser.inspect(@agent)
  end

  def major?
    true
  end

  def place
    @agent.dropped
    @registry.unregister(self)
  end

  def cancel
    @agent.dropped
    @browser.dismiss(@agent)
    @registry.unregister(self)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    place
  end

  def handle(event : SF::Event::MouseMoved)
    coords = @browser.pixel_to_protoplasm(event.x.at(event.y))

    @agent.dragged(coords - @agent.mid)
  end

  def handle(event : SF::Event::KeyPressed)
    case event.code
    when .escape?, .delete?, .backspace?
      cancel
      raise EndHandlingEvent.new(event)
    when .enter?
      place
      raise EndHandlingEvent.new(event)
    end
  end

  def handle(event : SF::Event::TextEntered)
    place
    @browser.inspect(@agent)
  end
end

class AgentDismisser < EventAuthority
  def initialize(registry : EventAuthorityRegistry, @browser : AgentBrowser)
    super(registry)

    @cursor = SF::Cursor.from_system(SF::Cursor::Type::Cross)
    @browser.push_cursor(@cursor)
  end

  def dismiss
    @browser.pop_cursor(@cursor)
    @registry.unregister(self)
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

    if agent = @browser.find_at_pixel?(coords, entity: Agent)
      @browser.dismiss(agent)
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

class SummonMenuDispatcher < EventAuthority
  def initialize(registry : EventAuthorityRegistry, @browser : AgentBrowser, pixel : Vector2, @parent : ProtocolAgent? = nil)
    super(registry)

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
    # Submit it to the browser so that the browser can draw it.
    #
    @browser.submit(@menu)

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
      agent = @browser.summon(cls, pixel: pixel)
      @browser.inspect(agent)
      protocol.connect(to: agent, in: @browser)
    else
      @registry.register AgentSummoner.new(@registry, @browser, agent: cls, pixel: pixel)
    end
  end

  def summon(cls : Agent.class, at pixel : Vector2)
    @registry.register AgentSummoner.new(@registry, @browser, agent: cls, pixel: pixel)
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

    summon(cls, at: @browser.mouse)

    cancel
  end

  # Closes the menu and unregisters self.
  def cancel
    @menu.close
    @registry.unregister(self)
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

class AgentBrowserDispatcher < EventAuthority
  def initialize(registry : EventAuthorityRegistry, @browser : AgentBrowser)
    super(registry)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    return unless event.clicks == 1

    coords = Vector2.new(event.x, event.y)

    @browser.editor_at_pixel?(coords) do |editor|
      editor.focus
      @registry.register DragHandler.new(@registry, editor, coords, oneshot: true)
      return
    end

    protoplasm = @browser.protoplasm_at_pixel?(coords)

    unless protoplasm && @browser.open?
      @browser.editor &.blur
    end

    # Open menu at the right-hand side.
    if protoplasm && event.button.right?
      @registry.register(SummonMenuDispatcher.new(@registry, @browser, pixel: coords))
      return
    end

    if agent = @browser.find_at_pixel?(coords, entity: Agent)
      case
      when @ctrl then agent = agent.copy(in: @browser)
      when @alt
        agent.toggle
        return
      end

      # Start inspecting the clicked-on agent, and register
      # a drag handler for it.
      @browser.inspect(agent)

      if @shift
        cont = SingleEdgeBuilder.new(@registry, @browser, agent)
      else
        cont = AgentDragHandler.new(@browser, @registry, agent, coords, oneshot: true)
      end

      @registry.register(cont)

      return
    end

    # If no agent to drag, register a handler to pan the protoplasm/editor.
    # Stop inspecting if we were, and the click was in the protoplasm.
    if protoplasm
      @browser.inspect(nil)
    end

    @registry.register DragHandler.new(@registry, @browser, coords, oneshot: true)
  end

  def forward(event : SF::Event)
    return unless @browser.open?

    @browser.editor &.handle(event)
  end

  @shift = false
  @ctrl = false
  @alt = false

  def handle(event : SF::Event::KeyPressed)
    @shift = event.shift || event.code.l_shift? || event.code.r_shift?
    @ctrl = event.control || event.code.l_control? || event.code.r_control?
    @alt = event.alt || event.code.l_alt? || event.code.r_alt?

    case event.code
    when .escape?
      if @browser.open?
        @browser.editor &.blur
        return
      else
        @browser.close
        return
      end
    when .delete?
      unless @browser.open?
        @registry.register AgentDismisser.new(@registry, @browser)
      end
    end

    forward(event)
  end

  def handle(event : SF::Event::KeyReleased)
    @shift = false if event.code.l_shift? || event.code.r_shift?
    @ctrl = false if event.code.l_control? || event.code.r_control?
    @alt = false if event.code.l_alt? || event.code.r_alt?

    forward(event)
  end

  def handle(event : SF::Event::MouseWheelScrolled)
    coords = event.x.at(event.y)
    agent = @browser.find_at_pixel?(coords, entity: Agent)
    if agent && agent.failed?
      event.delta.negative? ? agent.to_next_error : agent.to_prev_error
    else
      # Add a bit of randomness. Otherwise the user may experience some
      # visual... weirdness in the editor in particular.
      @browser.dragged((@shift ? event.delta.x : event.delta.y) * (5..15).sample)
    end
  end

  def handle(event : SF::Event)
    forward(event)
  end
end

class EdgeCreator < EventAuthority
  def initialize(registry : EventAuthorityRegistry, @browser : AgentBrowser)
    super(registry)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    return unless event.clicks == 2

    #
    # Find out the agent on which the user clicked.
    #
    return unless agent = @browser.find_at_pixel?(Vector2.new(event.x, event.y), entity: Agent)

    #
    # If the user indeed clicked on an agent, but nothing (of value)
    # is being inspected, switch to EdgeBuilder.
    #
    if !@browser.@protoplasm.@lens.aiming_at?(Agent) || @browser.@protoplasm.@lens.aiming_at?(agent)
      @registry.register MultiEdgeBuilder.new(@registry, @browser, agent)
      return
    end

    #
    # Otherwise, try to connect to one of the selected agents.
    #
    @browser.@protoplasm.@lens.each do |other|
      next unless other.is_a?(Agent)
      next unless agent.compatible?(other, in: @browser)

      agent.connect(to: other, in: @browser)
    end
  end

  def handle(event : SF::Event::KeyPressed)
    return if @browser.open? && @browser.editor &.focused?
    return unless @browser.@protoplasm.@lens.aiming_at?(Agent)

    case event.code
    when .enter?
      @browser.@protoplasm.@lens.each do |entity|
        next unless entity.is_a?(Agent)
        @registry.register MultiEdgeBuilder.new(@registry, @browser, entity)
        return
      end
    end
  end
end

abstract class EdgeBuilder < EventAuthority
  @edge : AgentPointEdge

  def initialize(registry : EventAuthorityRegistry, @browser : AgentBrowser, @agent : Agent)
    super(registry)

    @edge = @browser.connect(@agent, @agent.mid)
    @halos = [] of Halo

    #
    # Find agents that self is compatible with, and add a halo to
    # them so that the user can see where they can connect.
    #
    @browser.each_agent do |other|
      next if @agent.same?(other)
      next unless @agent.compatible?(other, in: @browser)

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
    @registry.unregister(self)
  end

  def handle(event : SF::Event::MouseMoved)
    coords = @browser.pixel_to_protoplasm?(event.x.at(event.y))

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
    other = @browser.find_at_pixel?(coords, entity: Agent)

    # If the user didn't click at an entity (and maybe clicked on void),
    # give them the summon menu.
    unless other
      cancel

      if protocol = @agent.as?(ProtocolAgent)
        @registry.register(SummonMenuDispatcher.new(@registry, @browser, coords, parent: protocol))
      end

      raise EndHandlingEvent.new(event)
    end

    # Cancel if over an agent but not compatible.
    unless @agent.compatible?(other, in: @browser)
      cancel

      raise EndHandlingEvent.new(event)
    end

    # If the user clicked at a *compatible* agent, make an edge with
    # that agent and cancel.
    @agent.connect(to: other, in: @browser)

    cancel
  end
end

class MultiEdgeBuilder < EdgeBuilder
  def handle(event : SF::Event::MouseButtonPressed)
    coords = Vector2.new(event.x, event.y)
    other = @browser.find_at_pixel?(coords)

    # If the user didn't click at an entity (and maybe clicked on void),
    # give them the summon menu.
    unless other
      cancel

      if protocol = @agent.as?(ProtocolAgent)
        @registry.register(SummonMenuDispatcher.new(@registry, @browser, coords, parent: protocol))
      end

      raise EndHandlingEvent.new(event)
    end

    # If the user clicked at an *incompatible* agent or another entity,
    # don't do anything, and ask the other handlers to skip the event.
    raise EndHandlingEvent.new(event) unless other.is_a?(Agent)
    raise EndHandlingEvent.new(event) unless @agent.compatible?(other, in: @browser)

    # If the user clicked at a *compatible* agent, make an edge with
    # that agent and cancel.
    @agent.connect(to: other, in: @browser)

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

  getter editor : AgentEditor

  @offset : Vector2

  def initialize(@browser : AgentBrowser, @editor : AgentEditor)
    @offset = Vector2.new(@editor.size/2) + (browser.size.y / 4).y
  end

  def dragged(delta : Vector2)
    @offset -= delta
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    # FIXME: view isn't seen anywhere; e.g. editor doesn't know it's
    # in a view -> drag + scroll doesn't work.
    view = target.view
    view.center = @offset.sfi
    target.view = view
    target.draw(@editor)
  end
end

class ErrorMessage
  def initialize(@message : String)
    @text = SF::Text.new(@message, FONT_BOLD, 11)
  end

  def size
    @text.size
  end

  def paint(*, on target : SF::RenderTarget, at point : Vector2)
    @text.position = point.sfi
    @text.fill_color = SF::Color.new(0xB7, 0x1C, 0x1C)
    target.draw(@text)
  end
end

class ErrorMessageViewer
  def initialize
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

  def clear
    @errors.clear
    @current = 0
  end

  def padding
    5.at(3)
  end

  def paint(*, on target : SF::RenderTarget, for agent : Agent)
    return unless any?

    error = @errors[@current]

    extent = Vector2.new(error.size) + padding*2
    origin = agent.mid - extent.y + agent.class.radius.xy * 1.5.at(-1.5)

    bg = SF::RectangleShape.new
    bg.position = origin.sfi
    bg.size = extent.sfi
    bg.fill_color = SF::Color.new(0xEF, 0x9A, 0x9A, 0xdd)

    src = agent.mid - agent.class.radius.y
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
    error.paint(on: target, at: origin + padding)

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

class AgentBrowser
  include IDraggable

  # Returns the size of this browser in pixels.
  getter size : Vector2

  @protoplasm : Protoplasm

  def initialize(@hub : AgentBrowserHub, @size : Vector2, @protoplasm : Protoplasm, @graph : AgentGraph)
    # Allocate 40% of width to the right-hand side editor panel, and
    # leave the rest to the protoplasm.
    @screen = SF::RenderTexture.new(size.x.to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @canvas = SF::RenderTexture.new((size.x * 0.6).to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @rpanel = SF::RenderTexture.new((size.x * 0.4).to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))

    # Create a texture with a dotted pattern
    dotted_image = SF::Image.new(100, 100, SF::Color.new(0x37, 0x37, 0x37))
    0.step(to: 99, by: 20) do |i|
      0.step(to: 99, by: 20) do |j|
        dotted_image.set_pixel(i, j, SF::Color.new(0x58, 0x58, 0x58))
        dotted_image.set_pixel(i + 1, j, SF::Color.new(0x52, 0x52, 0x52))
        dotted_image.set_pixel(i, j + 1, SF::Color.new(0x55, 0x55, 0x55))
      end
    end
    @dotted_texture = SF::Texture.from_image(dotted_image)
    @dotted_texture.repeated = true

    @animator_inout = Animator.new(1.second) do |progress|
      1 - Math.sqrt(1 - (1 - progress) ** 2)
    end

    @protoplasm.each_agent do |agent|
      agent.register(in: self)
    end
  end

  delegate :connect, :disconnect, :connected?, :each_protocol_agent, :each_rule_agent, to: @graph
  delegate :mouse, :push_cursor, :pop_cursor, to: @hub

  def close
    @hub.close
  end

  def summon(cls : Agent.class)
    agent = cls.new(@protoplasm)
    agent.register(in: self)
    agent.summon
    agent
  end

  def summon(cls : Agent.class, *, coords : Vector2)
    agent = summon(cls)
    agent.mid = coords
    agent
  end

  def summon(cls : Agent.class, *, pixel : Vector2)
    summon(cls, coords: pixel_to_protoplasm(pixel))
  end

  def dismiss(agent : Agent)
    inspect(nil) do
      agent.unregister(in: self)

      @graph.disconnect(agent)

      agent.dismiss
    end
  end

  @states = {} of UInt64 => EditorPanel
  @editor : EditorPanel?
  @menu : Menu?

  def submit(editor : AgentEditor)
    @states[editor.object_id] = EditorPanel.new(self, editor)
  end

  def submit(menu : Menu)
    @menu.try &.close
    @menu = menu
  end

  def withdraw(editor : AgentEditor)
    @states.delete(editor.object_id)
  end

  def submitted!(editor : AgentEditor)
    unless @states.has_key?(editor.object_id)
      raise "AgentBrowser: cannot use an editor that was not submitted"
    end
  end

  def editor(&)
    @editor.try { |state| yield state.editor }
  end

  def open?
    !!@editor
  end

  def editor_focused?
    editor { |editor| return editor.focused? }

    false
  end

  def open?(editor : AgentEditor)
    !!@editor.try &.editor.same?(editor)
  end

  def open(editor : AgentEditor, for opener : Agent)
    submitted!(editor)

    editor do |prev|
      next if prev.same?(editor)

      prev.blur

      # Gracefully close the previous editor if the new editor
      # is different.
      close(prev)
    end

    editor.focus

    @editor = @states[editor.object_id]
    @animator_inout.animate
  end

  def close(editor : AgentEditor)
    submitted!(editor)

    puts "close #{editor}"
  end

  def edit(entity : Agent)
    entity.edit(in: self)
  end

  def edit(entity : Nil)
    editor do |prev|
      prev.blur

      close(prev)

      @editor = nil
      @animator_inout.animate
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

  def register(registry : EventAuthorityRegistry)
    registry.register(AgentBrowserDispatcher.new(registry, self))
    registry.register(EdgeCreator.new(registry, self))
  end

  def unregister(registry : EventAuthorityRegistry)
    registry.clear
  end

  @draggable : IDraggable?

  def lifted
    @draggable = protoplasm_at_pixel?(mouse) ? self : @editor
  end

  def dragged(delta : Vector2)
    draggable = @draggable
    draggable ||= @editor unless protoplasm_at_pixel?(mouse)
    draggable ||= self

    #
    # If there is an explicit draggable and it's not self, redirect
    # drag to it. Otherwise, use canvas as the surface.
    #
    unless same?(draggable)
      draggable.dragged(delta)
      return
    end

    view = @canvas.view
    view.move(-delta.sfi)
    @canvas.view = view
  end

  def dropped
    @draggable = nil
  end

  def tick(delta : Float)
    @animator_inout.tick(delta)
    @protoplasm.tick(delta)
  end

  def hint
    <<-END
    • <Left click> -- focus and edit an agent
    • <Right click> -- summon an agent
    • <Double click>, <Shift-Drag> -- connect agents
    • <Drag> an agent -- move it
    • <Drag> empty space -- pan
    • <Ctrl-Drag> -- copy an agent
    • <Delete> -- dismiss an agent
    END
  end

  # Specifies the background color of this editor.
  def background_color
    SF::Color.new(0x31, 0x31, 0x31)
  end

  # Refreshes the underlying texture.
  private def refresh
    @canvas.clear(background_color)
    edges = SF::VertexArray.new(SF::Lines)
    @graph.each_edge &.draw(to: edges)
    @canvas.draw(edges)
    @protoplasm.draw(:entities, @canvas)
    # dd = SFMLDebugDraw.new(@canvas)
    # dd.draw(@protoplasm.@space)

    @canvas.display
    @rpanel.clear(SF::Color.new(0x37, 0x37, 0x37))
    origin = @rpanel.view.center - @rpanel.size/2
    if @editor
      sprite = SF::Sprite.new(@dotted_texture)
      sprite.texture_rect = SF.int_rect(origin.x.to_i, origin.y.to_i, @rpanel.size.x, @rpanel.size.y)
      sprite.position = origin
      @rpanel.draw(sprite)
    end

    if state = @editor
      @rpanel.draw(state)
    else
      rpanel_hint = SF::Text.new(hint, FONT_ITALIC, 11)
      rpanel_hint.color = SF::Color.new(0x99, 0x99, 0x99)
      rpanel_hint.position = (@rpanel.view.center - rpanel_hint.size/2).to_i
      @rpanel.draw(rpanel_hint)
    end

    if 1.0 - @animator_inout.value > 0.01
      rpanel_opacity_overlay = SF::RectangleShape.new
      rpanel_opacity_overlay.position = origin
      rpanel_opacity_overlay.fill_color = SF::Color.new(0x44, 0x44, 0x44, (@animator_inout.value * 255).to_i)
      rpanel_opacity_overlay.size = @rpanel.size
      @rpanel.draw(rpanel_opacity_overlay)
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

class Animator
  getter value

  def initialize(@span : Time::Span, &@animatee : Float64 -> Float64)
    @progress = 0.0
    @value = 0.0
    @start = nil
  end

  def tick(delta : Float)
    return unless start = @start

    @progress = (Time.monotonic - start)/@span
    if @progress > 1.0
      @start = nil
      @progress = 0.0
      return
    end

    @value = @animatee.call(@progress)
  end

  def animate
    @progress = 0.0
    @start = Time.monotonic
    @value = @animatee.call(@progress)
  end
end

struct MouseManager
  @cursors = [] of SF::Cursor

  def initialize(@window : SF::RenderWindow)
  end

  def position
    Vector2.new @window.map_pixel_to_coords(SF::Mouse.get_position(@window))
  end

  def push(cursor : SF::Cursor)
    @cursors << cursor
    @window.mouse_cursor = cursor
  end

  def pop(cursor : SF::Cursor)
    @cursors.delete_at(@cursors.rindex(cursor) || raise "cursor was not pushed: #{cursor}")
    @window.mouse_cursor = @cursors.last? || SF::Cursor.from_system(SF::Cursor::Type::Arrow)
  end
end

class AgentBrowserHub
  include SF::Drawable

  property position : Vector2 = 0.at(0)
  getter size : Vector2

  def initialize(@mouse : MouseManager, @size)
    @registry = EventAuthorityRegistry.new
    @watch = TimeTable.new(ClockAuthority.new)
  end

  def close
    App.the.tank.inspect(nil)
  end

  def mouse
    App.the.coords(@mouse.position) - position
  end

  def push_cursor(cursor : SF::Cursor)
    @mouse.push(cursor)
  end

  def pop_cursor(cursor : SF::Cursor)
    @mouse.pop(cursor)
  end

  @bmap = {} of Cell => AgentBrowser
  @browsers = [] of AgentBrowser

  def browser?
    @browsers.last?
  end

  def browse(cell : Cell)
    @browsers.last?.try &.unregister(@registry)

    browser = @bmap[cell]? || raise "BUG: cell must be registered first before use in shared CellBrowser!"
    browser.register(@registry)

    @browsers << browser
  end

  def upload(cell : Cell)
    browser = @browsers.pop
    browser.inspect(nil)
    browser.unregister(@registry)
    @browsers.last?.try &.register(@registry)
  end

  def register(cell : Cell)
    @bmap[cell] = cell.browse(self, size)
  end

  def register(cell : Cell, agent : Agent)
    agent_browser = @bmap[cell]
    agent.register(in: agent_browser)
  end

  def unregister(cell : Cell)
    @bmap.delete(cell)
  end

  @clicks = 0
  @mouseup : SF::Event::MouseButtonReleased?
  @mousedown : SF::Event::MouseButtonPressed?
  @mousedown_at : Vector2?
  @click_timeout : UUID?

  def handle(event : SF::Event::MouseButtonPressed)
    @clicks += 1
    @mousedown = event

    @click_timeout ||= @watch.after(150.milliseconds) do
      @mousedown.try do |event|
        event.clicks = @clicks
        @registry.dispatch(event)
      end
      @mouseup.try { |event| @registry.dispatch(event) }
      @clicks = 0
      @click_timeout = nil
      @mouseup = nil
      @mousedown = nil
    end
  end

  def handle(event : SF::Event::MouseButtonReleased)
    if @mousedown
      @mouseup = event
      return
    end

    @registry.dispatch(event)
  end

  def handle(event : SF::Event::MouseMoved)
    if (md = @mousedown) && (event.x.at(event.y) - md.x.at(md.y)).magn > 4 # 4px
      @mousedown.try do |event|
        event.clicks = @clicks
        @registry.dispatch(event)
      end
      @mouseup.try { |event| @registry.dispatch(event) }
      @clicks = 0
      @watch.cancel(@click_timeout.not_nil!)
      @click_timeout = nil
      @mouseup = nil
      @mousedown = nil
      return
    end

    @registry.dispatch(event)
  end

  def handle(event : SF::Event)
    @registry.dispatch(event)
  end

  def tick(delta : Float)
    @watch.tick
    browser?.try &.tick(1/60)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    browser?.try &.draw do |sprite|
      sprite.position = position.sfi
      sprite.draw(target, states)
    end
  end
end

# TODO:
#
# [x] connect agents with struts
# [x] port right-click menu
# [x] implement error overlay & halo for one or more errors
# [x] when an agent is paused (a boolean flag), it's darkened and a "paused"
#     icon appears on it
# [x] implement deletion of agents/protocols
# [x] implement ctrl-drag to copy rule within protocol and ctrl-drag to
#     copy entire protocol
# [x] bridge with protocols & rules: be able to initialize a AgentBrowser
#     from a protocolcollection & keep it there, agents own rules/protocols?
# [x] when AgentBrowser receives message, it forwards to matching protocol?
# [x] when protocol receives message, it forwards to matching agent?
# [x] when agent receives message, it executes matching rule?
# [x] heartbeatagent triggers its rule on tick?
# [ ] refactor into an isolated, connectable component & document
#   [ ] split agent browser into... something.. s? it's too big and does
#       too much. also eventhandler and eventhandlerstore are bad names
#       for what they do / what is done with them -- they have much more
#       agency than simple event handlers
# [x] merge with the main editor
# [x] implement play/pause for protocols which is triggered by Protocol#enable/
#     Protocol#disable/etc.
# [ ] implement play/pause for protoplasm (that is, for Tank)
# [ ] use play/pause on tank as an implementation of play/pause instead
#     of the weird ClockAuthority stuff -- implement TimeTable#pause and
#     TimeTable#unpause.
# [ ] add a GUI way to pause/unpause individual cells
# [x] add a GUI way to pause/unpause individual rules
# [x] add a GUI way to pause/unpause individual protocols
