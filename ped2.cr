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
require "./keyword_input"
require "./param_input"
require "./rule_header"
require "./rule_code_row"
require "./keyword_rule_header"

FONT        = SF::Font.from_memory({{read_file("./fonts/code/scientifica.otb")}}.to_slice)
FONT_BOLD   = SF::Font.from_memory({{read_file("./fonts/code/scientificaBold.otb")}}.to_slice)
FONT_ITALIC = SF::Font.from_memory({{read_file("./fonts/code/scientificaItalic.otb")}}.to_slice)

FONT.get_texture(11).smooth = false
FONT_BOLD.get_texture(11).smooth = false
FONT_ITALIC.get_texture(11).smooth = false

FONT_UI        = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Regular.ttf")}}.to_slice)
FONT_UI_MEDIUM = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Medium.ttf")}}.to_slice)
FONT_UI_BOLD   = SF::Font.from_memory({{read_file("./fonts/ui/Roboto-Bold.ttf")}}.to_slice)

# ----------------------------------------------------------

class RuleEditorState < BufferEditorColumnState
  def min_size
    1 # Rule header
  end

  def max_size
    2 # Rule header & rule code
  end

  def new_substate_for(index : Int)
    {KeywordRuleHeaderState, RuleCodeRowState}[index].new
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
    {KeywordRuleHeaderView, RuleCodeRowView}[index].new
  end

  def draw(target, states)
    #
    # Draw background rectangle.
    #
    bgrect = SF::RectangleShape.new
    bgrect.position = position
    bgrect.size = size
    bgrect.fill_color = SF::Color.new(0x31, 0x31, 0x31)
    bgrect.outline_color = active? ? SF::Color.new(0x43, 0x51, 0x80) : SF::Color.new(0x39, 0x39, 0x39)
    bgrect.outline_thickness = 1

    bgrect.draw(target, states)

    if @views.size > 1
      botrect = SF::RectangleShape.new
      botrect.position = SF.vector2f(position.x, position.y)
      botrect.size = SF.vector2f(size.x, @views[0].size.y)
      botrect.fill_color = SF::Color.new(0x39, 0x39, 0x39)
      botrect.draw(target, states)
    end

    super
  end
end

module RuleEditorHandler
  def handle!(editor : RuleEditorState, event : SF::Event::KeyPressed)
    return if editor.empty?

    if event.code.escape?
      blur
      return
    end

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

class RuleEditor
  include MonoBufferController(RuleEditorState, RuleEditorView)

  include BufferEditorHandler
  include BufferEditorRowHandler
  include RuleEditorHandler
end

# ----------------------------------------------------------

# TODO:
# [ ] Have a column of RuleEditors (RuleEditorColumn) where the
#     last RuleEditor is going to be the "insertion point" -- if
#     you type there a new empty rule editor appears below, and
#     this one is yours to change.
#
# [ ] Backspace in an empty ruleeditor should remove it unless it
#     is the last (insertion point) rule editor.
#
# [ ] Implement HeartbeatRule, BirthRuleEditor. ??? how to create them?
#
# [ ] RuleEditor can submit its RuleEditorState to an existing
#     Rule object on C-s, can fill its RuleEditorState from an
#     existing Rule object when not focused, when focused can
#     observe an existing RuleObject and show sync/out of sync
#     circle.
#
# [ ] Implement ProtocolEditor which is basically a big-smooth-
#     font editable name (a subset of InputField) followed by
#     RuleEditorColumn.
#
# [ ] ProtocolEditor can submit its ProtocolEditorState to an existing
#     Protocol object on C-s, can observe & fill its ProtocolEditorState
#     from an existing Protocol object when not focused, alternatively
#     (when focused) show sync/out of sync circle.
#
# [ ] Replace the current Protocol/Rule/ProtocolEditor system
#     with this new one.

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
