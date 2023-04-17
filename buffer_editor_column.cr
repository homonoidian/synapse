# A time-ordered snapshot of `BufferEditorColumnState`.
#
# Allows clients to implement an undo/redo system independent
# of `BufferEditorColumnState`.
#
# Also allows clients to peek into `BufferEditorColumnState`
# at discrete time steps for change-awareness.
record BufferEditorColumnInstant,
  timestamp : Int64,
  states : Array(BufferEditorRowInstant),
  selected : Int32

# Controls a column of `BufferEditorRow`s with one currently
# `selected` row.
class BufferEditorColumnState < DimensionState(BufferEditorRowState)
  def new_substate_for(index : Int) : BufferEditorRowState
    BufferEditorRowState.new
  end

  def capture
    BufferEditorColumnInstant.new(Time.local.to_unix, @states.map &.capture, @selected)
  end

  def after_moved_left(state : BufferEditorRowState)
    state.to_first
  end

  def after_moved_right(state : BufferEditorRowState)
    state.to_last
  end
end

# A column of `BufferEditorRow`s.
class BufferEditorColumnView < DimensionView(BufferEditorRowView, BufferEditorColumnInstant, BufferEditorRowInstant)
  # Specifies the height of whitespace separating row views
  # in this column.
  def wsheight
    11
  end

  def new_subview_for(index : Int) : BufferEditorRowView
    BufferEditorRowView.new
  end

  def arrange_cons_pair(left : BufferEditorRowView, right : BufferEditorRowView)
    right.position = SF.vector2f(left.position.x, left.position.y + left.size.y + wsheight)
  end

  def size : SF::Vector2f
    return SF.vector2f(0, 0) if @views.empty?

    SF.vector2f(@views.max_of(&.size.x), @views.sum(&.size.y) + wsheight * (@views.size - 1))
  end
end

# Provides the includer with a suite of `handle!` methods for
# controlling a `BufferEditorColumnState`.
#
# Unhandled events are delegated to the selected row. Includer
# must discard them properly, be a `BufferEditorRowHandler`,
# or treat them otherwise.
module BufferEditorColumnHandler
  # Applies *event* to the given *column* or, alternatively, to
  # the selected row.
  def handle!(column : BufferEditorColumnState, event : SF::Event::KeyPressed)
    return if column.empty?

    row = column.selected

    s = row.first_selected? && row.cursor_at_start? ? event.code : Ignore.new
    e = row.last_selected? && row.cursor_at_end? ? event.code : Ignore.new

    case {event.code, s, e}
    when {.enter?, _, _}     then column.split(backwards: event.shift)
    when {.up?, _, _}        then column.to_prev
    when {.down?, _, _}      then column.to_next
    when {_, .home?, _}      then column.to_first
    when {_, _, .end?}       then column.to_last
    when {_, .backspace?, _} then column.merge(forward: false)
    when {_, _, .delete?}    then column.merge(forward: true)
    else
      return handle!(row, event)
    end

    refresh
  end

  # :ditto:
  def handle!(column : BufferEditorColumnState, event : SF::Event)
    return if column.empty?

    handle!(column.selected, event)
  end
end

# A column of `BufferEditorRow`s with the ability to move
# between rows when the selected row's cursor is at either of
# the row's extremities (i.e., first column first character,
# last column last character inside the selected row).
class BufferEditorColumn
  include MonoBufferController(BufferEditorColumnState, BufferEditorColumnView)

  include BufferEditorHandler
  include BufferEditorRowHandler
  include BufferEditorColumnHandler
end
