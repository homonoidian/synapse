require "crsfml"

require "./ext"

require "./line"
require "./buffer"
require "./controller"
require "./dimension"
require "./buffer_editor"
require "./buffer_editor_row"
require "./buffer_editor_column"
require "./input_field"
require "./input_field_row"

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

class RuleHeaderView < InputFieldRowView
  property padding = SF.vector2f(8, 3)

  def new_subview_for(index : Int)
    index == 0 ? KeywordInputView.new : super
  end

  def origin
    position + padding
  end

  def size : SF::Vector2f
    super + padding * 2
  end
end

# ----------------------------------------------------------

class RuleEditorState < BufferEditorColumnState
  def new_substate_for(index : Int)
    # Auto append an input field state to new rows so they
    # aren't empty on creation.
    row = super
    row.append(InputFieldState.new)
    row
  end
end

class RuleEditorView < BufferEditorColumnView
  def wsheight
    0
  end

  def new_subview_for(index : Int)
    if index < 3
      RuleHeaderView.new.as(BufferEditorRowView)
    else
      BufferEditorRowView.new
    end
  end

  def draw(target, states)
    #
    # Draw background rectangle.
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

it_state = RuleEditorState.new
it_state.append
it_state.append
it_state.append
# pp it.to_next
# pp it.selected
# pp it
it_view = RuleEditorView.new
it_view.active = true
it_view.position = SF.vector2f(100, 200)

it = BufferEditorColumn.new(it_state, it_view)

# pp it_view

# TODO: buffer editor column

# state = KeywordRuleEditorState.new
# view = KeywordRuleEditorView.new
# view.position = SF.vector2f(100, 100)
# view.padding = SF.vector2f(5, 3)

# editor = KeywordRuleEditor.new(state, view)

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "App")
window.framerate_limit = 60

state0 = InputFieldRowState.new
state0.append
view0 = RuleHeaderView.new
view0.active = true
row0 = BufferEditorRow.new(state0, view0)

###

state1 = BufferEditorRowState.new
state1.append
view1 = BufferEditorRowView.new
view1.position = SF.vector2f(0, 50)
view1.active = true
row1 = BufferEditorRow.new(state1, view1)

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    end
    it.handle(event)
    # row0.handle(event)
    # row1.refresh
  end
  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  window.draw(it)
  window.display
end
