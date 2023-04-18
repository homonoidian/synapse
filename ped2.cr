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

class KeywordInputState < InputFieldState
  def insertable?(printable : String)
    super && !(' '.in?(printable) || '\t'.in?(printable))
  end
end

class ParamInputState < KeywordInputState
end

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

class RuleHeaderState < InputFieldRowState
  def min_size
    1
  end

  def new_substate_for(index : Int)
    index == 0 ? KeywordInputState.new : ParamInputState.new
  end
end

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

class RuleCodeView < BufferEditorRowView
  property padding_x = SF.vector2f(8, 8)
  property padding_y = SF.vector2f(0, 6)

  def origin
    position + SF.vector2f(padding_x.x, padding_y.x)
  end

  def size
    super + SF.vector2f(padding_x.x + padding_x.y, padding_y.x + padding_y.y)
  end
end

# ----------------------------------------------------------

class CodeEditorState < BufferEditorRowState
  def min_size
    1
  end

  def max_size
    1
  end
end

class RuleEditorState < BufferEditorColumnState
  def min_size
    1
  end

  def max_size
    2
  end

  def new_substate_for(index : Int)
    case index
    when 0
      row = RuleHeaderState.new
      row
    else
      CodeEditorState.new
    end
  end
end

class RuleEditorView < BufferEditorColumnView
  def wsheight
    0
  end

  def min_size
    SF.vector2f(40 * 6, 0)
  end

  def size
    super.max(min_size)
  end

  def new_subview_for(index : Int)
    case index
    when 0 then RuleHeaderView.new
    when 1 then RuleCodeView.new
    else
      raise "BUG: unreachable"
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

    if active?
      bgrect.outline_color = SF::Color.new(0x43, 0x51, 0x80)
      bgrect.outline_thickness = 1
    end

    bgrect.draw(target, states)

    super
  end
end

module RuleEditorHandler
  def handle!(editor : RuleEditorState, event : SF::Event::KeyPressed)
    return if editor.empty?

    # Row is rule header row or code row.
    row = editor.selected

    h = editor.first_selected? ? event.code : Ignore.new
    c = editor.size == 2 && editor.last_selected? ? event.code : Ignore.new

    case {h, c}
    when {.space?, _}
      # Spaces are not allowed in the keyword/params, so we can use
      # it as an alternative to tab.
      row.split(backwards: event.shift)
    when {.down?, _}, {.enter?, _}
      # Pressing down arrow inside header will select code
      # (creating it if none).
      if editor.size == 1
        editor.append
      end
      cursor = row.cursor
      editor.to_next
      code_row = editor.selected
      code = code_row.selected
      code.to_column(Math.min(cursor, code.line.size))
      refresh
      return
    when {_, .backspace?}
      # Pressing backspace at the first character of code,
      # if code is empty, will remove the code.
      if row.selected.at_start_index? && row.selected.empty?
        editor.drop
        refresh
        return
      end
    when {_, .up?}
      # Pressing up arrow at the first line of code will select
      # the header.
      if row.selected.at_first_line?
        cursor = row.cursor
        editor.to_prev
        header_row = editor.selected
        header_row.cursor = cursor
        refresh
        return
      end
    end

    handle!(row, event)
  end

  @pressed : SF::Vector2f?

  def handle!(column : BufferEditorColumnState, event : SF::Event::MouseButtonPressed)
    @pressed = SF.vector2f(event.x, event.y)
  end

  def handle!(column : BufferEditorColumnState, event : SF::Event::MouseButtonReleased)
    @pressed = nil
  end

  def handle!(column : BufferEditorColumnState, event : SF::Event::MouseMoved)
    return unless pressed = @pressed

    @view.position += SF.vector2f(event.x, event.y) - pressed
    @pressed = SF.vector2f(event.x, event.y)

    refresh
  end

  # :ditto:
  def handle!(column : RuleEditorState, event : SF::Event)
    return if column.empty?

    handle!(column.selected, event)
  end
end

# TODO: RuleEditor is 1x RuleHeader, 1x Code. Cannot add, cannot
# remove -- custom RuleEditorHandler.
class RuleEditor
  include MonoBufferController(RuleEditorState, RuleEditorView)

  include BufferEditorHandler
  include BufferEditorRowHandler
  include RuleEditorHandler
end

# ----------------------------------------------------------

#
# TODO: RuleEditorColumn

it_state = RuleEditorState.new
it_view = RuleEditorView.new
it_view.active = true
it_view.position = SF.vector2f(100, 200)

it = RuleEditor.new(it_state, it_view)

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "App")
window.framerate_limit = 60

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
  end
  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  window.draw(it)
  window.display
end
