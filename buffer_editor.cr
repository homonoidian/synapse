# A time-ordered snapshot of `BufferEditorState`.
#
# Allows clients to implement an undo/redo system independent
# of `BufferEditorState`.
#
# Also allows clients to peek into `BufferEditorState` at
# discrete time steps for change-awareness.
record BufferEditorInstant, timestamp : Int64, string : String, cursor : Int32

# Wraps some user-friendly editor logic around a string.
class BufferEditorState
  def initialize(value = "", @cursor = 0)
    @buffer = TextBuffer.new(value)
  end

  # Returns the string content of this state.
  def string
    @buffer.string
  end

  # Primitive: updates the buffer.
  #
  # **Unchecked**: may invalidate the state. Make sure to
  # `seek!` to a valid index afterwards.
  def update!(&)
    @buffer.update { |string| yield string }
  end

  # Primitive: moves cursor to *index*. Clamps if out of bounds
  # after update (see `start_index`, `end_index`).
  def seek!(index : Int)
    @cursor = index.clamp(start_index..end_index)
  end

  # Captures and returns an instant of this state.
  #
  # See `BufferEditorInstant`.
  def capture
    BufferEditorInstant.new(Time.local.to_unix, string, @cursor)
  end

  # Moves cursor to *index*.
  #
  # Noop if *index* is out of bounds.
  def seek(index : Int)
    return unless index.in?(start_index..end_index)

    seek!(index)
  end

  # Returns whether to allow insertion of *printable*.
  def insertable?(printable : String)
    true
  end

  # Returns the amount of characters in the text buffer.
  def size
    end_index - start_index
  end

  # Returns whether there are no characters in the text buffer.
  def empty?
    size.zero?
  end

  # Returns the index of the first character in the text buffer.
  def start_index
    0
  end

  # Returns the index *after* the last character in the text buffer.
  # This index acts as an insertion point.
  def end_index
    @buffer.size
  end

  # Returns the index *of* the last character in the text buffer.
  def max_index
    end_index - 1
  end

  # Returns whether the cursor is positioned at the first
  # character of the text buffer.
  def at_start_index?
    @cursor == start_index
  end

  # Returns whether the cursor is positioned at the last
  # character of the text buffer.
  def at_end_index?
    @cursor == end_index
  end

  # Moves the cursor to the start of the text buffer.
  def to_start_index
    seek!(start_index)
  end

  # Moves the cursor to the end of the text buffer.
  def to_end_index
    seek!(end_index)
  end

  # Finds out what line *index* is part of, and returns that
  # line. Raises if *index* is out of bounds.
  def index_to_line(index : Int)
    @buffer.line_at(index)
  end

  # Returns the line that includes the cursor.
  def line
    index_to_line(@cursor)
  end

  # Returns the line above the line that includes the cursor.
  # Raises if there is no such line.
  def line_above
    @buffer.fetch_line(line.ord - 1)
  end

  # Returns the line below the line that includes the cursor.
  # Raises if there is no such line.
  def line_below
    @buffer.fetch_line(line.ord + 1)
  end

  # Returns whether the cursor is positioned in the first line
  # of the buffer.
  def at_first_line?
    line.first?
  end

  # Returns whether the cursor is positioned in the last line
  # of the buffer.
  def at_last_line?
    line.last?
  end

  # Returns whether the cursor is at the start of the current line.
  def at_line_start?
    @cursor == line.b
  end

  # Returns whether the cursor is at the end of the current line.
  def at_line_end?
    @cursor == line.e
  end

  # Moves the cursor to the start of the current line.
  def to_line_start
    seek(line.b)
  end

  # Moves the cursor to the end of the current line.
  def to_line_end
    seek(line.e)
  end

  # Returns the column number (starting from 0) of the cursor.
  def column
    @cursor - line.b
  end

  # Moves the cursor to the given *column* in the current line.
  #
  # Clamps *column* to line bounds.
  def to_column(column : Int)
    seek(line.b + column.clamp(0..line.size))
  end

  # Moves the cursor to the next character (*wordstep* is false)
  # or word end (*wordstep* is true).
  #
  # Noop if there is no next character or word end.
  def to_right_bound(wordstep : Bool = false)
    return if at_end_index?

    seek!(wordstep ? @buffer.word_end_at(@cursor + 1) : @cursor + 1)
  end

  # Moves the cursor to the previous character (*wordstep* is false)
  # or word start (*wordstep* is true).
  #
  # Noop if there is no previous character or word start.
  def to_left_bound(wordstep : Bool = false)
    return if at_start_index?

    seek!(wordstep ? @buffer.word_begin_at(@cursor - 1) : @cursor - 1)
  end

  # Moves the cursor to the line above, or to the beginning of
  # the current line if there is no line above.
  def to_line_above
    line.first? ? to_line_start : to_line_above!
  end

  # Moves the cursor to the line below, or to the end of the
  # current line if there is no line below.
  def to_line_below
    line.last? ? to_line_end : to_line_below!
  end

  # Moves the cursor to the line above. Raises if there is no
  # line above.
  def to_line_above!
    above = line_above

    seek!(above.b + Math.min(column, above.size))
  end

  # Moves the cursor to the line below. Raises if there is no
  # line below.
  def to_line_below!
    below = line_below

    seek!(below.b + Math.min(column, below.size))
  end

  # Moves the contents of the text buffer to the system clipboard.
  def to_clipboard
    SF::Clipboard.string = @buffer.string
  end

  # *Wipes out* the text buffer and fills it with the contents
  # of the system clipboard. Moves the cursor to the end of the
  # text buffer.
  def from_clipboard
    string = SF::Clipboard.string

    return unless insertable?(string)

    update! { string }
    to_end_index
  end

  # Returns the string from the start index up to the cursor.
  # Returns an empty string if the cursor is at the start index.
  def before_cursor : String
    return "" if at_start_index?

    @buffer.slice(start_index, @cursor - 1)
  end

  # **Destructive**: deletes what comes from the start index
  # up to the cursor.
  def delete_before_cursor
    return if at_start_index?

    delete_at(start_index...@cursor)
  end

  # Returns the string from the cursor up to the end index.
  # Returns an empty string if the cursor is at the end index.
  def after_cursor : String
    return "" if at_end_index?

    @buffer.slice(@cursor, max_index)
  end

  # **Destructive**: deletes what comes from the start index
  # up to the cursor.
  def delete_after_cursor
    return if at_end_index?

    delete_at(@cursor..max_index)
  end

  # **Destructive**: clears the text buffer from the start index
  # to the maximum index, and moves the cursor to the start index.
  def clear
    delete_at(start_index..max_index)

    to_start_index
  end

  # Inserts a newline at the cursor. Line indentation before
  # the cursor is kept.
  def newline
    line = self.line
    head = String.build do |io|
      io << '\n'

      next if at_line_start?
      line.each_char do |char|
        break unless char.in?(' ', '\t')
        io << char
      end
    end

    insert(head)
  end

  # Inserts indentation.
  def indent
    insert("  ")
  end

  # Inserts *printable* where the cursor is positioned. Moves
  # the cursor after the inserted object.
  def insert(printable : Char)
    insert(printable.to_s)
  end

  # :ditto:
  def insert(printable : String)
    return unless insertable?(printable)

    insert_at(@cursor, printable)
    seek!(@cursor + printable.size)
  end

  # Translates the cursor position by *translation*, and deletes a
  # character (*wordstep* is false) or a word (*wordstep* is true).
  #
  # Noop if there is nothing to delete.
  def delete(wordstep = false, translation = 0)
    index = @cursor + translation

    wordstep ? delete_word(index) : delete_char(index)
  end

  private def delete_word(index : Int32)
    is_before_cursor = index < @cursor

    i1 = is_before_cursor ? @buffer.word_begin_at(index) : @buffer.word_end_at(index) - 1
    i2 = index

    return unless i1.in?(start_index..end_index) && i2.in?(start_index..end_index)

    b = Math.min(i1, i2)
    e = Math.max(i1, i2)

    delete_at(b..e)

    return unless is_before_cursor

    seek!(@cursor - (e - b + 1))
  end

  private def delete_char(index : Int32)
    delta = index - @cursor

    return unless index.in?(start_index..max_index)

    delete_at(index)
    seek!(@cursor + delta)
  end

  # Inserts *printable* at the given *index*.
  #
  # Raises if *index* is out of bounds.
  def insert_at(index : Int, printable : String)
    update! &.insert(index, printable)
  end

  # Deletes character(s) at the given *index*.
  #
  # Raises if *index* is out of bounds.
  def delete_at(index : Range | Int)
    update! &.delete_at(index)
  end
end

# An `SF::Drawable` view of `BufferEditorState`.
class BufferEditorView
  include IView

  def initialize
    @text = SF::Text.new("", font, font_size)
    @text.line_spacing = line_spacing

    @beam = SF::RectangleShape.new
  end

  # Synchronizes the contents of this view according to *instant*.
  def update(instant : BufferEditorInstant)
    @text.string = instant.string

    cur = find_character_pos(instant.cursor)
    nxt = find_character_pos(instant.cursor + 1)

    @beam.position = cur + beam_margin
    @beam.size = beam_size(cur, nxt)
  end

  # Synchronizes the contents of this view according to *state*.
  def update(state : BufferEditorState)
    update(state.capture)
  end

  # Returns the font used in this view.
  def font
    FONT
  end

  # Returns the font size (in pixels) used in this view.
  def font_size
    11
  end

  # Line height as a multiple of font size.
  def line_spacing
    1.3
  end

  # Returns the line height used in this view.
  def line_height
    font_size * line_spacing
  end

  # Computes the size (width, height) of the beam given the
  # positions of the character under the cursor, *cur*, and
  # the character after the cursor, *nxt*.
  def beam_size(cur : SF::Vector2, nxt : SF::Vector2)
    SF.vector2f(Math.max(5, nxt.x - cur.x), font_size)
  end

  # Returns the color used for the text contents of this view.
  def text_color
    SF::Color.new(0xE0, 0xE0, 0xE0)
  end

  # Returns the color used for the cursor beam.
  def beam_color
    SF::Color.new(0x9E, 0x9E, 0x9E)
  end

  # Returns the margin of the beam inside a line.
  def beam_margin # FIXME: should be private/inline, currently used by ProtocolEditor#draw() for rule headers
    SF.vector2f(0, Math.max(2, @text.character_size * (@text.line_spacing - 1)/2))
  end

  def position
    @text.position.to_i
  end

  def position=(position : SF::Vector2)
    delta = position - self.position

    @text.position += delta
    @beam.position += delta
  end

  # Specifies snap grid step for size.
  def snapstep
    SF.vector2f(6, 0)
  end

  # Returns the snapped full width and height of this view.
  def size
    SF.vector2f(
      Math.max(@beam.size.x, @text.size.x),
      Math.max(line_height, @text.size.y)
    ).snap(snapstep).to_i
  end

  # Returns the position of the character at the given *index*.
  #
  # Raises if *index* is out of bounds.
  def find_character_pos(index : Int)
    @text.find_character_pos(index)
  end

  def draw(target, states)
    if active?
      @beam.fill_color = beam_color
      @beam.draw(target, states)
    end

    @text.fill_color = text_color
    @text.draw(target, states)
  end
end

# Provides the includer with a suite of `handle!` methods for
# controlling a `BufferEditorState`.
#
# The provided methods **do not** manage focus.
module BufferEditorHandler
  # Applies *event* to the given buffer editor *ed*.
  def handle!(ed : BufferEditorState, event : SF::Event::KeyPressed)
    case event.code
    when .delete?    then ed.delete(wordstep: event.control, translation: 0)
    when .backspace? then ed.delete(wordstep: event.control, translation: -1)
    when .enter?     then ed.newline
    when .tab?       then ed.indent
    when .left?      then ed.to_left_bound(wordstep: event.control)
    when .right?     then ed.to_right_bound(wordstep: event.control)
    when .up?        then ed.to_line_above
    when .down?      then ed.to_line_below
    when .home?      then ed.to_line_start
    when .end?       then ed.to_line_end
    when .c?
      return unless event.control

      ed.to_clipboard
    when .v?
      return unless event.control

      ed.from_clipboard
    end

    refresh
  end

  # :ditto:
  def handle!(ed : BufferEditorState, event : SF::Event::TextEntered)
    chr = event.unicode.chr

    return unless chr.printable?

    ed.insert(chr)

    refresh
  end

  # :ditto:
  def handle!(ed : BufferEditorState, event : SF::Event)
  end
end

# An isolated, user-friendly, single-cursor `TextBuffer` editor.
#
# * Receives and executes SFML events.
# * Can be drawn like any other SFML drawable.
class BufferEditor
  include MonoBufferController(BufferEditorState, BufferEditorView)
  include BufferEditorHandler
end

# TODO: undo/redo by copying BufferModel
