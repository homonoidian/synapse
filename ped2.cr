require "crsfml"

require "./ext"

require "./line"
require "./buffer"
require "./buffer_editor"
require "./input_field"
require "./buffer_editor_row"

FONT        = SF::Font.from_memory({{read_file("./fonts/code/scientifica.otb")}}.to_slice)
FONT_BOLD   = SF::Font.from_memory({{read_file("./fonts/code/scientificaBold.otb")}}.to_slice)
FONT_ITALIC = SF::Font.from_memory({{read_file("./fonts/code/scientificaItalic.otb")}}.to_slice)

FONT_UI        = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Regular.ttf")}}.to_slice)
FONT_UI_MEDIUM = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Medium.ttf")}}.to_slice)
FONT_UI_BOLD   = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Bold.ttf")}}.to_slice)

# ----------------------------------------------------------

class KeywordInputView < InputFieldView
  def font
    FONT_ITALIC
  end

  def underline_color
    SF::Color.new(0xcf, 0x89, 0x9f)
  end

  def beam_color
    SF::Color.new(0xfa, 0xb1, 0xc7)
  end

  def text_color
    SF::Color.new(0xcf, 0x89, 0x9f)
  end
end

# ----------------------------------------------------------

class InputFieldRowState < BufferEditorRowState
  def new_substate_for(index)
    InputFieldState.new
  end
end

class InputFieldRowView < BufferEditorRowView
  def new_subview_for(index)
    InputFieldView.new
  end
end

# ----------------------------------------------------------

class RuleHeaderView < InputFieldRowView
  property padding = SF.vector2f(8, 3)

  def new_subview_for(index)
    index == 0 ? KeywordInputView.new : super
  end

  def origin
    position + padding
  end

  def size
    super + padding * 2
  end

  def draw(target, states)
    #
    # Draw background rectangle.
    #
    # FIXME: remove this, draw bg rect in buffer editor column
    #
    bgrect = SF::RectangleShape.new
    bgrect.position = position
    bgrect.size = size
    bgrect.fill_color = SF::Color.new(0x31, 0x31, 0x31)
    bgrect.draw(target, states)

    super
  end
end

# ----------------------------------------------------------

# TODO: buffer editor column

# state = KeywordRuleEditorState.new
# view = KeywordRuleEditorView.new
# view.position = SF.vector2f(100, 100)
# view.padding = SF.vector2f(5, 3)

# editor = KeywordRuleEditor.new(state, view)

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "App")
window.framerate_limit = 60

state = InputFieldRowState.new
# state.append

view = RuleHeaderView.new
view.active = true

ed = BufferEditorRow.new(state, view)

ed.refresh

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::KeyEvent
      # pp ed.@state.cursor
    end
    ed.handle(event)
  end
  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  window.draw(ed)
  window.display
end
