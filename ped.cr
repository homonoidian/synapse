require "uuid"
require "crsfml"

require "./ext"

require "./line"
require "./buffer"
require "./buffer_editor"
require "./input_field"

FONT        = SF::Font.from_memory({{read_file("./fonts/code/scientifica.otb")}}.to_slice)
FONT_BOLD   = SF::Font.from_memory({{read_file("./fonts/code/scientificaBold.otb")}}.to_slice)
FONT_ITALIC = SF::Font.from_memory({{read_file("./fonts/code/scientificaItalic.otb")}}.to_slice)

FONT_UI        = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Regular.ttf")}}.to_slice)
FONT_UI_MEDIUM = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Medium.ttf")}}.to_slice)
FONT_UI_BOLD   = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Bold.ttf")}}.to_slice)

FONT.get_texture(11).smooth = false
FONT_BOLD.get_texture(11).smooth = false
FONT_ITALIC.get_texture(11).smooth = false

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "Protocol Editor")
window.framerate_limit = 60

def keyword_input(buffer, position)
  view = InputFieldView.new
  view.position = position

  {InputField.new(InputFieldState.new(buffer), view), view}
end

def param_input(buffer, position)
  view = InputFieldView.new
  view.position = position

  {InputField.new(InputFieldState.new(buffer), view), view}
end

focused_field = 0

fields = [
  keyword_input(TextBuffer.new, SF.vector2f(100, 100)),
  param_input(TextBuffer.new, SF.vector2f(160, 100)),
  param_input(TextBuffer.new, SF.vector2f(200, 100)),
]
fields[focused_field][0].focus

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::KeyPressed
      if event.code.tab?
        to_index = (focused_field + (event.shift ? -1 : 1)) % fields.size

        next unless (from = fields[focused_field][0]).can_blur?
        next unless (to = fields[to_index][0]).can_focus?

        from.blur
        to.focus
        focused_field = to_index

        next
      end
    end
    fields[focused_field][0].handle(event)
    fields.each_cons_pair do |(a, av), (b, bv)|
      av_corner = av.position + av.size
      bv.position = SF.vector2f(av_corner.x + 6, bv.position.y)
    end
  end

  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  fields.each do |field, _|
    window.draw(field)
  end
  window.display
end

# TODO: highlight current field in blue [x]
# TODO: backspace in empty field deletes the field [ ]
# TODO: enter inserts a field after the current field [ ]
# TODO: tab at the end inserts a field [ ]
# TODO: start with only the keyword field [ ]
# TODO: draw gray-ish (lifted) background rect with focused/blurred gray outline [ ]
# TODO: add big source code buffer editor [ ]
# TODO: pressing down moves into the buffer editor [ ]
# TODO: pressing up at the 0th character of the buffer editor moves to first parameter [ ]
# TODO: draw background rect under buffer editor with sync (ok blue/error red) outline (2 x lifted) [ ]
# TODO: extract component KeywordRuleEditor, HeartbeatRuleEditor
# TODO: support validation of input fields with red highlight and pointy error [ ]
#   keyword -- anything
#   params -- letters followed by symbols
#   heartbeat time -- digits followed by s or ms
#
