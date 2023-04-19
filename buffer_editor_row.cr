# A time-ordered snapshot of `BufferEditorRowState`.
#
# Allows clients to implement an undo/redo system independent
# of `BufferEditorRowState`.
#
# Also allows clients to peek into `BufferEditorRowState` at
# discrete time steps for change-awareness.
record BufferEditorRowInstant,
  timestamp : Int64,
  states : Array(BufferEditorInstant),
  selected : Int32

# Controls a row of `BufferEditorState`s with one currently
# `selected` state.
class BufferEditorRowState < DimensionState(BufferEditorState)
  def sepsize
    1
  end

  def new_substate_for(index : Int) : BufferEditorState
    BufferEditorState.new
  end

  def capture
    BufferEditorRowInstant.new(Time.local.to_unix, @states.map(&.capture), @selected)
  end

  def after_moved_left(state : BufferEditorState)
    state.to_start_index
  end

  def after_moved_right(state : BufferEditorState)
    state.to_end_index
  end

  def splitdist(left : BufferEditorState, right : BufferEditorState)
    lhalf = left.before_cursor
    rhalf = left.after_cursor

    left.update! { lhalf }
    right.update! { rhalf }
  end

  def merge!
    string = selected.capture.string

    super

    selected.update! { |it| it + string }
  end

  # Returns cursor column number *as if this row was a single
  # buffer editor* arranged in a virtual "line".
  #
  # Returns 0 if there are no editor states.
  def column
    return 0 if empty?

    cursor = selected.capture.cursor
    cursor += (first_index...@selected).sum { |n| nth(n).size + 1 }
    cursor
  end

  # Seeks *column* *as if this row was a single buffer editor*.
  #
  # Does nothing if there are no editor states. Moves the cursor
  # to the last character of the last editor state if *column*
  # exceeds the total amount of characters in this row, including
  # `sepsize` per separator.
  def to_column(column : Int)
    return if empty?

    (0...@states.size).accumulate(0) do |offset, index|
      state = @states[index]

      if column.in?(offset..offset + state.size)
        to_nth(index)

        state.to_start_index
        state.to_column Math.min(column - offset, state.line.size)

        return
      end

      offset + state.size + sepsize
    end

    to_last
  end
end

# A row of `BufferEditorView`s.
class BufferEditorRowView < DimensionView(BufferEditorView, BufferEditorRowInstant, BufferEditorInstant)
  # Specifies the width of whitespace separating editor views
  # in this row.
  def wswidth
    6
  end

  def new_subview_for(index : Int) : BufferEditorView
    BufferEditorView.new
  end

  def arrange_cons_pair(left : BufferEditorView, right : BufferEditorView)
    right.position = SF.vector2f(
      left.position.x + left.size.x + wswidth,
      left.position.y
    )
  end

  def size : SF::Vector2f
    return SF.vector2f(0, 0) if @views.empty?

    SF.vector2f(
      @views.sum(&.size.x) + wswidth * (@views.size - 1),
      @views.max_of(&.size.y)
    )
  end
end

# Provides the includer with a suite of `handle!` methods for
# controlling a `BufferEditorRowState`.
#
# Unhandled events are delegated to the selected editor. Includer
# must discard them properly, be a `BufferEditorHandler`, or
# treat them otherwise.
module BufferEditorRowHandler
  # Applies *event* to the given *row* or, alternatively, to
  # the selected editor.
  def handle!(row : BufferEditorRowState, event : SF::Event::KeyPressed)
    return if row.empty?

    s = row.cursor_at_start? ? event.code : Ignore.new
    e = row.cursor_at_end? ? event.code : Ignore.new

    begin
      case {event.code, s, e}
      when {.tab?, _, _}       then row.split(backwards: event.shift)
      when {_, .left?, _}      then row.to_prev
      when {_, _, .right?}     then row.to_next
      when {_, .home?, _}      then row.to_first
      when {_, _, .end?}       then row.to_last
      when {_, .backspace?, _} then row.merge(forward: false)
      when {_, _, .delete?}    then row.merge(forward: true)
      else
        return handle!(row.selected, event)
      end
    rescue DimensionOverflowException | DimensionUnderflowException
      # In case of underflow/overflow simply redirect to the
      # selected editor.
      return handle!(row.selected, event)
    end

    refresh
  end

  # :ditto:
  def handle!(row : BufferEditorRowState, event : SF::Event)
    return if row.empty?

    handle!(row.selected, event)
  end
end

# A row of `BufferEditor`s with the ability to move between
# editors when the selected editor's cursor is at either of
# the extremities.
#
# The selected editor can be sliced in half by pressing Tab.
# Tabbing at the beginning or end will result in an empty
# half before or after the cursor, correspondingly -- in other
# words, will result in insertion of new columns.
class BufferEditorRow
  include MonoBufferController(BufferEditorRowState, BufferEditorRowView)

  include BufferEditorHandler
  include BufferEditorRowHandler
end
