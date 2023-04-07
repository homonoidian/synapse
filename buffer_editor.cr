# A time-ordered snapshot of `BufferEditorState`.
#
# Allows clients to implement an undo/redo system independent
# of `BufferEditorState`.
#
# Also allows clients to peek into `BufferEditorState` at
# discrete time steps for change-awareness.
record BufferEditorInstant, timestamp : Int64, string : String, cursor : Int32

# Wraps some user-friendly editor logic around a `TextBuffer`.
class BufferEditorState
  def initialize(@buffer = TextBuffer.new, @cursor = 0)
  end

  # Primitive: updates the buffer.
  #
  # **Unchecked**: may invalidate the state.
  private def update!(&)
    @buffer.update { |string| yield string }
  end

  # Primitive: moves cursor to *index*.
  #
  # **Unchecked**: may invalidate the state.
  private def seek!(index : Int)
    @cursor = index
  end

  # Captures and returns an instant of this state.
  #
  # See `BufferEditorInstant`.
  def capture
    BufferEditorInstant.new(Time.local.to_unix, @buffer.string, @cursor)
  end

  # Moves cursor to *index*.
  #
  # Noop if *index* is out of bounds.
  def seek(index : Int)
    return unless index.in?(0..size)

    seek!(index)
  end

  # Returns the amount of characters in the text buffer.
  def size
    @buffer.size
  end

  # Returns the start index of this text buffer.
  def start
    0
  end

  # Returns the end index of this text buffer.
  def end
    size - 1
  end

  # Returns whether the cursor is positioned at the beginning
  # of the text buffer.
  def at_start?
    @cursor == start
  end

  # Returns whether the cursor is positioned at the end of
  # the text buffer.
  def at_end?
    @cursor == self.end
  end

  # Returns whether to allow insertion of *printable*.
  def insertable?(printable : String)
    true
  end

  # Moves the cursor to the start of the text buffer.
  def to_start
    seek!(start)
  end

  # Moves the cursor to the end of the text buffer.
  def to_end
    seek!(self.end)
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

  # Moves the cursor to the next character (*wordstep* is false)
  # or word end (*wordstep* is true).
  #
  # Noop if there is no next character or word end.
  def forward(wordstep : Bool = false)
    return if at_end?

    seek!(wordstep ? @buffer.word_end_at(@cursor + 1) : @cursor + 1)
  end

  # Moves the cursor to the previous character (*wordstep* is false)
  # or word start (*wordstep* is true).
  #
  # Noop if there is no previous character or word start.
  def backward(wordstep : Bool = false)
    return if at_start?

    seek!(wordstep ? @buffer.word_begin_at(@cursor - 1) : @cursor - 1)
  end

  # Moves the cursor to the line above, or to the beginning of
  # the current line if there is no line above.
  def upward
    line.first? ? to_line_start : upward!
  end

  # Moves the cursor to the line below, or to the end of the
  # current line if there is no line below.
  def downward
    line.last? ? to_line_end : downward!
  end

  # Moves the cursor to the line above. Raises if there is no
  # line above.
  def upward!
    above = line_above

    seek!(above.b + Math.min(column, above.size))
  end

  # Moves the cursor to the line below. Raises if there is no
  # line below.
  def downward!
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
    to_end
  end

  # Inserts a newline at the cursor. Line indentation before
  # the cursor is kept.
  def newline
    line = self.line
    head = String.build do |io|
      io << '\n'

      next if @cursor == line.b
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

    i1 = is_before_cursor ? @buffer.word_begin_at(index) : @buffer.word_end_at(index)
    i2 = index

    return unless i1.in?(0...size) && i2.in?(0...size)

    b = Math.min(i1, i2)
    e = Math.max(i1, i2)

    delete_at(b..e)

    return unless is_before_cursor

    seek!(@cursor - (e - b + 1))
  end

  private def delete_char(index : Int32)
    delta = index - @cursor

    return unless index.in?(0...size)

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
  include SF::Drawable

  # Determines whether this view is active.
  property? active = true

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
    @beam.size = SF.vector2f(Math.max(4, nxt.x - cur.x), font_size)
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

  # Returns the color used for the text contents of this view.
  def text_color
    SF::Color.new(0xee, 0xee, 0xee)
  end

  # Returns the color used for the cursor beam.
  def beam_color
    SF::Color.new(0x9E, 0x9E, 0x9E)
  end

  # Returns the margin of the beam inside a line.
  def beam_margin # FIXME: should be private/inline, currently used by ProtocolEditor#draw() for rule headers
    SF.vector2f(0, @text.character_size * (@text.line_spacing - 1)/2)
  end

  # Returns the position of this view.
  def position
    @text.position
  end

  # Translates this view to *position*.
  def position=(position : SF::Vector2)
    delta = position - @text.position

    @text.position += delta
    @beam.position += delta
  end

  # Returns the full width and height of this view.
  def size
    @text.size
  end

  # Returns the position of the character at the given *index*.
  #
  # Raises if *index* is out of bounds.
  def find_character_pos(index : Int)
    @text.find_character_pos(index)
  end

  def draw(target, states)
    if active?
      @beam.draw(target, states)
      @beam.fill_color = beam_color
    end

    @text.fill_color = text_color
    @text.draw(target, states)
  end
end

# An isolated, user-friendly, single-cursor `TextBuffer` editor.
#
# * Receives SFML events using `handle`.
# * Can be drawn like any other SFML drawable.
class BufferEditor
  include SF::Drawable

  def initialize(@state : BufferEditorState, @view : BufferEditorView)
    refresh
  end

  # Updates the view according to the state.
  def refresh
    @view.update(@state)
  end

  # Returns whether this editor can accept focus.
  def can_focus?
    true
  end

  # Returns whether this editor can release focus.
  def can_blur?
    true
  end

  # Accepts focus.
  def focus
  end

  # Releases focus.
  def blur
  end

  # Updates editor state based on *event*.
  def handle(event : SF::Event::KeyPressed)
    case event.code
    when .backspace? then @state.delete(wordstep: event.control, translation: -1)
    when .delete?    then @state.delete(wordstep: event.control)
    when .enter?     then @state.newline
    when .tab?       then @state.indent
    when .left?      then @state.backward(wordstep: event.control)
    when .right?     then @state.forward(wordstep: event.control)
    when .home?      then @state.to_line_start
    when .end?       then @state.to_line_end
    when .up?        then @state.upward
    when .down?      then @state.downward
    when .c?
      return unless event.control

      @state.to_clipboard
    when .v?
      return unless event.control

      @state.from_clipboard
    else
      return
    end

    refresh
  end

  # :ditto:
  def handle(event : SF::Event::TextEntered)
    chr = event.unicode.chr

    return unless chr.printable?

    @state.insert(chr)

    refresh
  end

  # :ditto:
  def handle(event)
  end

  def draw(target, states)
    @view.draw(target, states)
  end
end
