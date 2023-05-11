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

# ---------------------------------------------------------------------

class Protoplasm < Tank
  def initialize
    super

    @space.gravity = CP.v(0, 0)
  end
end

module IDraggable
  abstract def lift
  abstract def drag(delta : Vector2)
  abstract def drop
end

abstract class RuleAgent < CircularEntity
  include SF::Drawable
  include IRemixIconView
  include Inspectable
  include IDraggable

  @editor : RuleEditor

  def initialize(tank : Protoplasm)
    super(tank, self.class.color, lifespan: nil)

    @editor = to_editor
  end

  abstract def to_editor : RuleEditor

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

  def lift
  end

  def drag(delta : Vector2)
    self.mid += delta
  end

  def drop
  end

  def open(in viewer : AgentViewer)
    return if viewer.editor_open?(@editor)

    @editor.position = (mid + Vector2.new(-@editor.size.x/2, self.class.radius * 4)).sf
    @editor.focus

    viewer.open(@editor)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
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
  end
end

class HeartbeatRuleAgent < RuleAgent
  def to_editor : RuleEditor
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
  def to_editor : RuleEditor
    BirthRuleEditor.new(BirthRuleEditorState.new, BirthRuleEditorView.new)
  end

  def icon
    Icon::BirthRule
  end

  def icon_color
    SF::Color.new(0xEE, 0xEE, 0xEE)
  end
end

class KeywordRuleAgent < RuleAgent
  def to_editor : RuleEditor
    KeywordRuleEditor.new(KeywordRuleEditorState.new, KeywordRuleEditorView.new)
  end

  def icon
    Icon::KeywordRule
  end

  def icon_color
    SF::Color.new(0x90, 0xCA, 0xF9)
  end
end


class EventHandlerStore
  def initialize
    @handlers = [] of EventHandler
  end

  def register(handler : EventHandler)
    @handlers << handler
  end

  def unregister(handler : EventHandler)
    @handlers.delete(handler)
  end

  def handle(event : SF::Event)
    @handlers.each &.handle(event)
  end
end

abstract class EventHandler
  def initialize(@handlers : EventHandlerStore)
  end

  def handle(event : SF::Event)
  end
end

class DragHandler < EventHandler
  @grip : Vector2?

  def initialize(handlers : EventHandlerStore, @item : IDraggable, @oneshot = false)
    super(handlers)
  end

  # Sends `lift` message to the item.
  def handle(event : SF::Event::MouseButtonPressed)
    @item.lift
    @grip = event.x.at(event.y)
  end

  # Sends `drop` message to the item.
  def handle(event : SF::Event::MouseButtonReleased)
    @item.drop
    @grip = nil
    @handlers.unregister(self) if @oneshot
  end

  # Sends `drag` message to the item if the item is being dragged.
  def handle(event : SF::Event::MouseMoved)
    return unless grip = @grip

    coords = event.x.at(event.y)

    @item.drag(coords - grip)
    @grip = coords
  end
end

class AgentSelectHandler < EventHandler
  def initialize(handlers : EventHandlerStore, @viewer : AgentViewer)
    super(handlers)
  end

  def handle(event : SF::Event::MouseButtonPressed)
    @viewer.editor_at_pixel?(Vector2.new(event.x, event.y)) do |editor|
      # TODO: make editors IDraggable instead of having another Draggable module
      editor.handle(event)
      return
    end

    if agent = @viewer.find_at_pixel?(Vector2.new(event.x, event.y), entity: RuleAgent)
      # Start inspecting the clicked-on agent, and register
      # a drag handler for it.
      @viewer.inspect(agent)
      @handlers.register DragHandler.new(@handlers, agent, oneshot: true)
      return
    end

    # If no agent to drag, register a handler to pan the protoplasm.
    # Stop inspecting if we were.
    @viewer.inspect(nil)
    @handlers.register DragHandler.new(@handlers, @viewer, oneshot: true)
  end

  def handle(event : SF::Event)
    return unless @viewer.editor_open?

    @viewer.editor &.handle(event)
  end
end

class AgentViewer
  include IDraggable

  # Returns the size of this viewer in pixels.
  getter size : Vector2

  def initialize(@size : Vector2)
    @canvas = SF::RenderTexture.new(size.x.to_i, size.y.to_i, SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @protoplasm = Protoplasm.new

    kw = KeywordRuleAgent.new(@protoplasm)
    kw.mid = 400.at(200)
    kw.summon

    br = BirthRuleAgent.new(@protoplasm)
    br.mid = 500.at(200)
    br.summon

  end

  @editor : RuleEditor?

  def editor(&)
    @editor.try { |editor| yield editor }
  end

  def editor_open?
    !!@editor
  end

  def editor_open?(editor : RuleEditor)
    @editor.same?(editor)
  end

  def open(editor : RuleEditor?)
    @editor.try do |prev|
      next if prev.same?(editor)

      # Gracefully close the previous editor if the new editor
      # is different.
      close(prev)
    end

    @editor = editor
  end

  def close(editor : RuleEditor)
    puts "close #{editor}"
  end

  def edit(entity : RuleAgent)
    entity.open(in: self)
  end

  def edit(entity : Nil)
    open(editor: nil)
  end

  def inspect(entity, &)
    @protoplasm.inspect(entity) do
      edit(entity)

      yield
    end
  end

  def inspect(entity)
    inspect(entity) { } 
  end

  def find_at_pixel?(pixel : Vector2, entity : T.class) forall T
    coords = Vector2.new @canvas.map_pixel_to_coords(pixel.sfi)

    @protoplasm.find_at?(coords, entity)
  end

  def editor_at_pixel?(pixel : Vector2, &)
    return unless editor = @editor

    coords = Vector2.new @canvas.map_pixel_to_coords(pixel.sfi)

    if editor.includes?(coords.sf)
      yield editor
    end
  end

  def register(handlers)
    handlers.register(AgentSelectHandler.new(handlers, self))
  end

  def lift
  end

  def drag(delta : Vector2)
    view = @canvas.view
    view.move(-delta.sfi)
    @canvas.view = view
  end

  def drop
  end

  def tick(delta : Float)
    @protoplasm.tick(delta)
  end

  # Specifies the background color of this editor.
  def background_color
    SF::Color.new(0x31, 0x31, 0x31)
  end

  # Refreshes the content of the underlying texture.
  def refresh
    @canvas.clear(background_color)
    @protoplasm.draw(:entities, @canvas)

    @editor.try do |editor|
      @protoplasm.@lens.each do |entity|
        next unless agent = entity.as?(RuleAgent)

        agent_points = {
          agent.mid - agent.class.radius.y, # North
          agent.mid + agent.class.radius.y, # South
          agent.mid - agent.class.radius.x, # West
          agent.mid + agent.class.radius.x, # East
        }

        editor_origin = Vector2.new(editor.position)
        editor_extent = Vector2.new(editor.size)

        editor_points = {
          editor_origin + editor_extent.ox/2, # Top middle
          editor_origin + editor_extent / 2.at(1), # Bottom middle
          editor_origin + editor_extent / 1.at(2), # Right middle
        }

        distance = nil
        min_src = nil
        min_dst = nil

        agent_points.each do |src|
          editor_points.each do |dst|
            magn = (dst - src).magn
            if distance.nil? || magn < distance
              min_src = src
              min_dst = dst
              distance = magn
            end
          end
        end

        src = min_src.not_nil!
        dst = min_dst.not_nil!
        dir = dst - src

        connector = SF::RectangleShape.new
        connector.size = SF.vector2f(dir.magn, 2)
        connector.position = src.sf
        connector.rotate(Math.degrees(Math.atan2(dir.y, dir.x)))
        connector.fill_color = SF::Color.new(0x43, 0x51, 0x80)
        @canvas.draw(connector)
      end

      @canvas.draw(editor)
    end


    @canvas.display
  end

  # Refreshes this editor, and yields an SFML Sprite object so that the
  # caller can position and draw it where desired.
  def draw(& : SF::Sprite ->)
    refresh

    yield SF::Sprite.new(@canvas.texture)
  end
end

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "Hello World", settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
window.framerate_limit = 60

handlers = EventHandlerStore.new

viewer = AgentViewer.new(600.at(400))
viewer.register(handlers)

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    end

    handlers.handle(event)
  end

  viewer.tick(1/60)

  window.clear(SF::Color::White)
  viewer.draw do |sprite|
    window.draw(sprite)
  end
  window.display
end
