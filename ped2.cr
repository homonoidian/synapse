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

# ----------------------------------------------------------

class KeywordInputView < InputFieldView
  def font
    FONT_ITALIC
  end

  def underline_color
    SF::Color.new(0xcf, 0x89, 0x9f)
  end

  def beam_color
    SF::Color.new(0x93, 0x52, 0x67)
  end

  def text_color
    SF::Color.new(0xcf, 0x89, 0x9f)
  end
end

class BufferEditorHStrip < BufferEditorCollection
  def initialize
    @states = [] of BufferEditorState
    @views = [] of BufferEditorView
    @cursor = 0
    @focused = true
  end

  getter cursor

  class RedirToField < Exception
  end

  def cursor=(other : Int32)
    if other < @cursor # move to left
      @states[@cursor].to_start_index
      @states[other].to_end_index
    elsif @cursor < other # move to right
      @states[@cursor].to_end_index
      @states[other].to_start_index
    end
    @views[@cursor].active = false
    @views[other].active = true
    @cursor = other
  end

  def gutter
    6
  end

  def refresh
    return if @states.empty? || @views.empty?

    @states.zip(@views) do |state, view|
      view.update(state)
    end

    @views.each_cons_pair do |a, b|
      b.position = SF.vector2f(a.position.x + a.size.x + gutter, b.position.y)
    end
  end

  def focus
    @views[@cursor].active = true

    refresh
  end

  def blur
    @views[@cursor].active = false

    refresh
  end

  def clear
    @states.clear
    @views.clear
    refresh
  end

  def index
    accum = @states[@cursor].capture.cursor
    (0...@cursor).each do |index|
      state = @states[index]
      accum += state.size + 1
    end
    accum
  end

  def insert_at(index, state, view)
    @states.insert(index, state)
    @views.insert(index, view)
  end

  def append(state, view)
    insert_at(@states.size, state, view)
  end

  def build
    {BufferEditorState.new, BufferEditorView.new}
  end

  def insert_at(cursor)
    insert_at(cursor, *build)
  end

  def each_state_and_view(& : BufferEditorState, BufferEditorView ->)
    @states.zip(@views) do |state, view|
      yield state, view
    end
  end

  def each_state(& : BufferEditorState ->)
    yield @states[@cursor]
  end

  def each_view(& : BufferEditorView ->)
    @views.each { |view| yield view }
  end

  def cursor_at_field_lbound?
    @states[@cursor].at_start_index?
  end

  def cursor_at_field_rbound?
    @states[@cursor].at_end_index?
  end

  def split_before
    return if @cursor == 0

    insert_at(@cursor)

    nxt_state = @states[@cursor + 1]
    nxt_before_curs = nxt_state.before_cursor
    nxt_after_curs = nxt_state.after_cursor

    nxt_state.update! { nxt_after_curs }
    @states[@cursor].update! { nxt_before_curs }

    @states[@cursor + 1].to_start_index
    @views[@cursor + 1].active = false

    @states[@cursor].to_end_index
    @views[@cursor].active = true
  end

  def split_after
    insert_at(@cursor + 1)

    before_curs = @states[@cursor].before_cursor
    after_curs = @states[@cursor].after_cursor

    nxt_state = @states[@cursor + 1]
    nxt_state.update! { after_curs }

    @states[@cursor].update! { before_curs }

    self.cursor += 1
  end

  def handle_at_field_lbound(event : SF::Event::KeyPressed)
    case event.code
    when .backspace?
      raise RedirToField.new unless @cursor > 0

      del_at = @cursor

      del_state = @states[del_at]
      del_string = del_state.capture.string
      del_state.clear

      self.cursor -= 1

      @states.delete_at(del_at)
      @views.delete_at(del_at)

      @states[@cursor].update! { |s| s + del_string }
    when .left?
      self.cursor = Math.max(0, cursor - 1)
    when .home?
      self.cursor = 0
      @states[@cursor].to_start_index
    else
      raise RedirToField.new
    end
  end

  def handle_at_field_rbound(event : SF::Event::KeyPressed)
    case event.code
    when .delete?
      raise RedirToField.new if @cursor == @states.size - 1

      del_at = @cursor + 1
      del_state = @states[del_at]
      del_string = del_state.capture.string
      del_state.clear

      @states.delete_at(del_at)
      @views.delete_at(del_at)

      @states[@cursor].update! { |s| s + del_string }
    when .right?
      self.cursor = Math.min(@states.size - 1, cursor + 1)
    when .end?
      self.cursor = @states.size - 1
      @states[@cursor].to_end_index
    else
      raise RedirToField.new
    end
  end

  def handle(event : SF::Event::KeyPressed)
    begin
      case event.code
      when .tab?
        event.shift ? split_before : split_after
        refresh
        return
      end

      # The precondition for the following event handling is that
      # the cursor must be at a boundary: either at the left or at
      # the right boundary of the field under the cursor.
      begin
        if cursor_at_field_lbound?
          handle_at_field_lbound(event)
          refresh
          return
        end
      rescue RedirToField
      end

      begin
        if cursor_at_field_rbound?
          handle_at_field_rbound(event)
          refresh
          return
        end
      rescue RedirToField
      end
    rescue RedirToField
    end

    super
  end
end

class InputFieldHStrip < BufferEditorHStrip
  def build
    {InputFieldState.new, InputFieldView.new}
  end
end

# ----------------------------------------------------------

# state = KeywordRuleEditorState.new
# view = KeywordRuleEditorView.new
# view.position = SF.vector2f(100, 100)
# view.padding = SF.vector2f(5, 3)

# editor = KeywordRuleEditor.new(state, view)

window = SF::RenderWindow.new(SF::VideoMode.new(800, 600), title: "App")
window.framerate_limit = 60

ed = InputFieldHStrip.new
ed.append(InputFieldState.new, KeywordInputView.new)
ed.refresh

while window.open?
  while event = window.poll_event
    case event
    when SF::Event::Closed then window.close
    when SF::Event::KeyEvent
      pp ed.index
    end
    ed.handle(event)
  end
  window.clear(SF::Color.new(0x21, 0x21, 0x21))
  window.draw(ed)
  window.display
end
