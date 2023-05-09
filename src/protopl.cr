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

    @space.gravity = CP.v(0, 9)
  end
end

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "Hello World")
window.framerate_limit = 60

protoplasm = Protoplasm.new

cell = CellAvatar.new(protoplasm, Cell.new)
cell.summon

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::MouseMoved
      cell.mid = Vector2.new(event.x, event.y)
    when SF::Event::TextEntered
      cell.emit("hello", 100.0, SF::Color::Black)
    end
  end
  protoplasm.tick(1/60)
  window.clear(SF::Color::White)
  protoplasm.draw(:entities, window)
  window.display
end
