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

class KeywordInputView < InputFieldView
  def font
    FONT_ITALIC
  end

  def text_color
    SF::Color.new(0xad, 0x65, 0xca)
  end
end

class KeywordInput < InputField
  def initialize(state : InputFieldState, view : KeywordInputView)
    super(state, view)
  end
end

class ParamInput < InputField
end

class CodeField < BufferEditor
end

def keyword_input(position)
  state = InputFieldState.new
  view = KeywordInputView.new
  view.position = position
  KeywordInput.new(state, view)
end

def param_input(position)
  state = InputFieldState.new
  view = InputFieldView.new
  view.position = position
  ParamInput.new(state, view)
end

def code_input(position)
  state = BufferEditorState.new
  view = BufferEditorView.new
  view.position = position
  CodeField.new(state, view)
end

class KeywordRuleEditor
  include SF::Drawable

  WS_WIDTH          =  6 # FIXME: compute from font
  LINE_HEIGHT       = 14
  CODE_INSET_SPACES =  2
  CODE_INSET_X      = WS_WIDTH * CODE_INSET_SPACES
  CODE_MARGIN_Y     = 16

  @pressed_id : Symbol?
  @code_field : CodeField

  def initialize
    @focused_field = 0
    @focused_code = false
    @origin = SF.vector2f(100, 100)

    @fields = [keyword_input(@origin)] of BufferEditor
    @fields[@focused_field].focus

    @code_field = code_input(@origin + SF.vector2f(CODE_INSET_X, LINE_HEIGHT + CODE_MARGIN_Y))
    @code_field.blur

    @sync = false
    @buttons = [] of {Symbol, SF::FloatRect}
    @code_field_was_opened = false
  end

  def try_give_focus_to_field?(index : Int, &) : Bool
    return false unless (from = @fields[@focused_field]).can_blur?
    return false unless (to = @fields[index]).can_focus?

    yield from, to

    from.blur
    to.focus

    @focused_field = index

    true
  end

  def try_give_focus_to_field?(index : Int) : Bool
    try_give_focus_to_field?(index) { }
  end

  def try_move_to_code_from_fields? : Bool
    return false unless (from = @fields[@focused_field]).can_blur?
    return false unless (to = @code_field).can_focus?

    @code_field_was_opened = true

    # Compute column in @fields

    col = 0
    @fields.each_with_index do |editor, index|
      break if index >= @focused_field
      col += editor.@state.size + 1
    end

    col += @fields[@focused_field].@state.column
    col -= CODE_INSET_SPACES

    col = Math.min(to.@state.line.size, col)
    to.@state.to_column(col)

    from.blur
    to.focus

    @focused_code = true

    true
  end

  def try_move_to_fields_from_code? : Bool
    return false unless @code_field.@state.at_first_line?
    # move up to @fields
    return false unless (from = @code_field).can_blur?

    # compute column in code
    code_col = @code_field.@state.column + CODE_INSET_SPACES

    # go thru @fields until all of them are exhausted or
    # code column is found
    #
    # the following assumes @fields are single-line!
    field_idx = 0
    field_inner_idx = nil
    to_index = @fields.size - 1
    @fields.each_with_index do |editor, index|
      next_field_idx = field_idx + editor.@state.size + 1 # plus whitespace between field
      if next_field_idx > code_col
        to_index = index
        field_inner_idx = code_col - field_idx
        break
      end
      field_idx = next_field_idx
    end

    return false unless (to = @fields[to_index]).can_focus?

    if field_inner_idx
      to.@state.seek(field_inner_idx)
    else
      to.@state.to_end_index
    end

    from.blur
    to.focus

    @focused_code = false
    @focused_field = to_index

    true
  end

  def try_move_to_next_field?(step : Int) : Bool
    to_index = @focused_field + step
    return true if to_index < 0

    if to_index >= @fields.size
      field = @fields[@focused_field]
      corner = field.@view.position + field.@view.size
      @fields << param_input(SF.vector2f(corner.x + WS_WIDTH, field.@view.position.y))
      to_index = @fields.size - 1 # clamp
    end

    try_give_focus_to_field?(to_index) do |from, to|
      if step.negative?
        from.@state.to_start_index
        to.@state.to_end_index
      else
        from.@state.to_end_index
        to.@state.to_start_index
      end
    end
  end

  def try_merge_current_field_into_previous_field? : Bool
    return false unless @focused_field > 0 && @fields[@focused_field].@state.at_start_index?

    try_give_focus_to_field?(@focused_field - 1) do |from, to|
      curr_string = from.@state.string

      # Clear existing field
      from.clear

      # Remove it
      @fields.delete_at(@focused_field)

      # Append
      prev_state = to.@state
      prev_state.update! { prev_state.string + curr_string }
    end
  end

  def try_merge_next_field_into_current_field? : Bool
    field = @fields[@focused_field]

    return false unless 0 <= @focused_field < @fields.size - 1 && field.@state.at_end_index?

    next_index = @focused_field + 1

    # first check whether it wants to unfocus and next
    # wants to focus
    return false unless (from = @fields[next_index]).can_blur?

    nxt = @fields[next_index]
    nxt.blur

    # buffer stores with newline at the end (always), use
    # rchop to omit it
    next_string = nxt.@state.string

    # Clear next field
    nxt.clear

    # Remove it
    @fields.delete_at(next_index)

    # focused field is already = next_index then

    # Prepend
    curr_state = @fields[@focused_field].@state
    # buffer stores with newline at the end (always), use
    # rchop to omit it
    curr_state.update! { curr_state.string + next_string }

    @fields[@focused_field].refresh

    true
  end

  def try_move_to_adjacent?(prev : Bool) : Bool
    return false unless (prev && @fields[@focused_field].@state.at_start_index?) || (!prev && @fields[@focused_field].@state.at_end_index?)
    # NOTE: almost the same as TAb/shift-tab but doesn't create anything
    to_index = (@focused_field + (prev ? -1 : 1))
    return false unless to_index.in?(0...@fields.size)

    try_give_focus_to_field?(to_index) do |from, to|
      if prev
        from.@state.to_start_index
        to.@state.to_end_index
      else
        from.@state.to_end_index
        to.@state.to_start_index
      end
    end

    true
  end

  def try_insert_field?(before : Bool) : Bool
    return false if @focused_field == 0 && before # can't insert before keyword
    ins_index = @focused_field + (before ? 0 : 1)

    return false unless (from = @fields[@focused_field]).can_blur?

    from_state = @fields[@focused_field].@state

    field = @fields[@focused_field].@view
    corner = field.position + field.size
    # insert with dummy position
    @fields.insert(ins_index, to = param_input(SF.vector2f(0, 0)))
    # recompute positions
    @fields.each_cons_pair do |a, b|
      av_corner = a.@view.position + a.@view.size
      b.@view.position = SF.vector2f(av_corner.x + WS_WIDTH, a.@view.position.y)
    end

    if before
      # shift-enter: move before cursor in from_buf to to_buf
      to.@state.update! { from_state.before_cursor }
      from_state.delete_before_cursor
    else
      # enter: move after cursor in from_buf to to_buf
      to.@state.update! { from_state.after_cursor }
      from_state.delete_after_cursor
    end

    from.blur
    @focused_field = ins_index

    if before
      from.@state.to_start_index
      to.@state.to_end_index
    else
      from.@state.to_end_index
      to.@state.to_start_index
    end
    to.focus

    true
  end

  def try_move_to_home? : Bool
    return false unless @fields[@focused_field].@state.at_start_index?

    try_give_focus_to_field?(0) # let dest  handle .home?

    false
  end

  def try_move_to_end? : Bool
    return false unless @fields[@focused_field].@state.at_end_index?

    try_give_focus_to_field?(@fields.size - 1) # let dest  handle .end?

    false
  end

  def handle?(event : SF::Event::KeyPressed) : Bool
    if @focused_code
      case event.code
      when .up? then try_move_to_fields_from_code?
      else
        false
      end
    else
      case event.code
      when .down?          then try_move_to_code_from_fields?
      when .tab?           then try_move_to_next_field?(step: event.shift ? -1 : 1)
      when .backspace?     then try_merge_current_field_into_previous_field?
      when .delete?        then try_merge_next_field_into_current_field?
      when .left?, .right? then try_move_to_adjacent?(prev: event.code.left?)
      when .enter?         then try_insert_field?(before: event.shift)
      when .home?          then try_move_to_home?
      when .end?           then try_move_to_end?
      else
        false
      end
    end
  end

  def handle?(event : SF::Event::MouseButtonReleased) : Bool
    pt = SF.vector2f(event.x, event.y)
    @buttons.each do |(id, button)|
      if button.contains?(pt) && @pressed_id == id
        puts "Pressed #{id}!"
        break
      end
    end
    @pressed_id = nil
    true
  end

  def handle?(event : SF::Event::MouseButtonPressed) : Bool
    pt = SF.vector2f(event.x, event.y)
    @buttons.each do |(id, button)|
      if button.contains?(pt)
        @pressed_id = id
      end
    end
    true
  end

  def handle?(event) : Bool
    false
  end

  def forward(event)
    if @focused_code
      @code_field.handle(event)
    else
      @fields[@focused_field].handle(event)
      @fields.each_cons_pair do |a, b|
        av_corner = a.@view.position + a.@view.size
        b.@view.position = SF.vector2f(av_corner.x + WS_WIDTH, b.@view.position.y)
      end
    end
  end

  def handle(event)
    handle?(event) || forward(event)
  end

  def draw(target, states)
    padding = SF.vector2f(8, 3)
    min_code_size = SF.vector2f(128, 64)

    # draw bgrect

    bgrect = SF::RectangleShape.new
    bgrect.position = @origin - padding

    fields_w = @fields.sum { |field| field.@view.size.x } + WS_WIDTH * @fields.size
    fields_h = @fields.max_of { |field| field.@view.size.y }

    computed_size = SF.vector2f(
      Math.max(fields_w, @code_field.@view.size.x + WS_WIDTH * CODE_INSET_SPACES*2),
      fields_h + LINE_HEIGHT + (@code_field_was_opened ? CODE_MARGIN_Y + @code_field.@view.size.y : 0)
    ) + padding*2
    bgrect.outline_thickness = 1
    bgrect.outline_color = SF::Color.new(0x61, 0x61, 0x61)
    if @code_field_was_opened
      bgrect.size = SF.vector2f(
        Math.max(computed_size.x, min_code_size.x),
        Math.max(computed_size.y, min_code_size.y),
      )
    else
      bgrect.size = SF.vector2f(
        Math.max(computed_size.x, min_code_size.x),
        computed_size.y
      )
    end

    bgrect.fill_color = SF::Color.new(0x32, 0x32, 0x32)
    bgrect.draw(target, states)

    action_w = 25
    action_px = 5
    action_py = 5

    # draw bg for accept/reject/ok
    bgaction = SF::RectangleShape.new
    bgaction.position = bgrect.position - SF.vector2f(action_w, 1)
    bgaction.size = SF.vector2f(action_w, (@code_field_was_opened ? min_code_size.y + padding.y : computed_size.y + padding.y) - 1)
    bgaction.fill_color = bgrect.outline_color
    bgaction.draw(target, states)

    btn_area = SF.vector2f(action_w - action_px*2, bgaction.size.y - action_py*2)
    btn_origin = bgaction.position + (bgaction.size - btn_area)/2

    @sync = !@focused_code

    @buttons.clear

    # draw ok
    if @sync
      okbtn = SF::RectangleShape.new
      okbtn.size = btn_area
      okbtn.position = btn_origin
      okbtn.fill_color = SF::Color.new(0x96, 0xad, 0xcc)
      okbtn.draw(target, states)
    else
      gap = 3
      subbtn_area = SF.vector2f(btn_area.x, btn_area.y / 2 - gap)
      btn_accept_origin = btn_origin
      btn_reject_origin = btn_origin + SF.vector2f(0, btn_area.y / 2 + gap)

      btn = SF::RectangleShape.new
      btn.size = subbtn_area
      # accept
      btn.position = btn_accept_origin
      btn.fill_color = SF::Color.new(0x9b, 0xb1, 0x91)
      btn.draw(target, states)
      @buttons << {:accept, btn.global_bounds}

      # reject
      btn.position = btn_reject_origin
      btn.fill_color = SF::Color.new(0xcb, 0x9f, 0xab)
      btn.draw(target, states)
      @buttons << {:reject, btn.global_bounds}
    end

    @fields.each do |field|
      field.draw(target, states)
    end

    if @code_field_was_opened
      # draw code field rect
      code_bgrect = SF::RectangleShape.new
      code_bgrect.position = SF.vector2f(@origin.x - padding.x, @code_field.@view.position.y - CODE_MARGIN_Y//2)
      code_bgrect.fill_color = SF::Color.new(0x32, 0x32, 0x32)
      code_bgrect.size = bgrect.size - SF.vector2f(0, fields_h + CODE_MARGIN_Y + 5)
      code_bgrect.draw(target, states)

      sep = SF::RectangleShape.new
      sep.position = code_bgrect.position - SF.vector2f(0, 2)
      sep.size = SF.vector2f(bgrect.size.x, 1)
      sep.fill_color = SF::Color.new(0x61, 0x61, 0x61)
      sep.draw(target, states)

      @code_field.draw(target, states)
    end
  end
end

editor = KeywordRuleEditor.new

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    end

    editor.handle(event)
  end

  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  window.draw(editor)
  window.display
end

# TODO: highlight current field in blue [x]
# TODO: tab at the end inserts a field [x]
# TODO: backspace at start of field deletes the field and appends its content into previous field [x]
# TODO: delete at end of field deletes the field and prepends its content into next field [x]
# TODO: pressing left at start moves into the field to the left [x]
# TODO: pressing right at end moves into the field to the right [x]
# TODO: enter inserts a field after the current field with moved content after cursor of current [x]
# TODO: shift-enter inserts a field before the current field with moved content before cursor of current [x]
# TODO: home at start moves to first field [x]
# TODO: end at end moves to last field [x]
#
# TODO: show underline only under the active field [x]
# TODO: start with only the keyword field [x]
# TODO: add source code buffer editor below [x]
# TODO: pressing down moves into the buffer editor [x]
# TODO: pressing up at the first line of the buffer editor moves into fields [x]
# TODO: pressing up moves to field "over" the cursor [x]
# TODO: pressing down moves to character "under" the field + cursor [x]
#
# TODO: draw gray-ish (lifted) background rect outline [x]
# TODO: draw background rect under buffer with outline (2 x lifted) [x]
# TODO: draw accept/reject buttons to the left of the background [x]
# TODO: alternatively (via a 'sync' flag), draw green rect to the left of the background [x]
# TODO: print message when accept/reject is clicked [x]
# TODO: do not draw buffer if it is empty and the user didn't navigate into it yet [x]
#
# TODO: extract component RuleEditor, KeywordRuleEditor, HeartbeatRuleEditor etc. with models,
#       make models take and talk to and edit corresponding rule objects (via pressing
#       accept/reject after edits [accept = C-s]; and monitoring whether model content == rule object content) [ ]
# TODO: highlight keyword in different color even when unfocused [x]
# TODO: support validation of input fields with red highlight and pointy error [ ]
#   keyword -- anything
#   params -- letters followed by symbols
#   heartbeat time -- digits followed by s or ms
#
# TODO: compactify the design [ ]
# TODO: draw multiple RuleEditors in a row [ ]
# TODO: when Up is pressed at start in ruleeditor, move to the ruleeditor above [ ]
# TODO: when Down is pressed at end in ruleeditor, move to the ruleeditor below [ ]
# TODO: when C-home is pressed move to first ruleeditor's home [ ]
# TODO: when C-end is pressed move to last ruleeditor's end [ ]
# TODO: there is always an empty rule at the bottom.when it is filled a new empty
# rule is created below [ ]
# TODO: extract component ProtocolEditor [ ]
# TODO: make ProtocolEditor take and talk to and edit Protocol [ ]
#
# TODO: merge into app.cr ProtocolEditor (rename what's currently there to CellEditor)[ ]
# TODO: design considerations [ ]
