# A time-ordered snapshot of `BufferEditorColumnState`.
#
# Allows clients to implement an undo/redo system independent
# of `BufferEditorColumnState`.
#
# Also allows clients to peek into `BufferEditorColumnState`
# at discrete time steps for change-awareness.
class BufferEditorColumnInstant < DimensionInstant(BufferEditorRowInstant)
end

# Controls a column of `BufferEditorRow`s with one currently
# `selected` row.
class BufferEditorColumnState < DimensionState(BufferEditorRowState)
  def new_substate_for(index : Int) : BufferEditorRowState
    BufferEditorRowState.new
  end

  def capture : BufferEditorColumnInstant
    BufferEditorColumnInstant.new(Time.local.to_unix, @states.map &.capture, @selected)
  end

  def after_moved_left(state : BufferEditorRowState)
    state.to_first
  end

  def after_moved_right(state : BufferEditorRowState)
    state.to_last
  end

  # If possible, moves the cursor in the selected row to *column*.
  #
  # See `BufferEditorRowState#to_column`.
  def to_column(column : Int)
    selected.to_column(column)
  end

  # Selects the previous row, and, if possible, moves the cursor
  # there to *column*.
  #
  # See `BufferEditorRowState#to_column`.
  def to_prev_with_column(column : Int)
    return if empty?

    to_prev
    to_column(column)
  end

  # Selects the next row, and, if possible, moves the cursor
  # there to *column*.
  #
  # See `BufferEditorRowState#to_column`.
  def to_next_with_column(column : Int)
    return if empty?

    to_next
    to_column(column)
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
    right.position = SF.vector2f(
      left.position.x,
      left.position.y + left.size.y + wsheight
    )
  end

  # Specifies snap grid step for size.
  def snapstep
    SF.vector2f(0, 0)
  end

  def size : SF::Vector2f
    return snapstep if @views.empty?

    SF.vector2f(
      @views.max_of(&.size.x),
      @views.sum(&.size.y) + wsheight * (@views.size - 1)
    ).snap(snapstep)
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

    begin
      case {event.code, s, e}
      when {.enter?, _, _}     then column.split(backwards: event.shift)
      when {_, .home?, _}      then column.to_first
      when {_, _, .end?}       then column.to_last
      when {_, .left?, _}      then column.to_prev
      when {_, _, .right?}     then column.to_next
      when {_, .backspace?, _} then column.merge(forward: false)
      when {_, _, .delete?}    then column.merge(forward: true)
      else
        return handle!(row, event)
      end
    rescue DimensionOverflowException | DimensionUnderflowException
      # In case of underflow/overflow simply redirect to the
      # selected row.
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
