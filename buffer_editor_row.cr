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

# Controls an array of `BufferEditorState`s with one currently
# *selected* editor.
class BufferEditorRowState
  def initialize
    @states = [] of BufferEditorState
    @selected = 0
  end

  # Captures and returns an instant of this editor row state.
  #
  # See `BufferEditorRowInstant`.
  def capture
    BufferEditorRowInstant.new(Time.local.to_unix, @states.map(&.capture), @selected)
  end

  # Returns whether there are currently no editors in this
  # editor row state.
  def empty?
    size.zero?
  end

  # Returns the amount of editors in this editor row state.
  def size
    @states.size
  end

  # Returns the index of the first editor state.
  def first_index
    0
  end

  # Returns the index of the last editor state.
  def last_index
    @states.size - 1
  end

  # Returns the index of the previous editor state.
  def prev_index
    @selected - 1
  end

  # Returns the index of the next editor state.
  def next_index
    @selected + 1
  end

  # Returns the *n*-th editor state, or raises.
  def nth(n : Int)
    @states[n]
  end

  # Returns the selected state.
  def selected
    nth(@selected)
  end

  # Returns whether the cursor is at the beginning of the
  # selected editor state.
  def cursor_at_start?
    return true if empty?

    selected.at_start_index?
  end

  # Returns whether the cursor is at the end of the selected
  # editor state.
  def cursor_at_end?
    return true if empty?

    selected.at_end_index?
  end

  # Returns whether the first editor state is selected.
  def first_selected?
    @selected == first_index
  end

  # Returns whether the last editor state is selected.
  def last_selected?
    @selected == last_index
  end

  # Selects *index*-th field. Clamps *index* to the bounds of
  # the editor states in this row.
  #
  # Does nothing if there are no editor states.
  def to_nth(index : Int)
    return if empty?

    @selected = @selected.clamp(first_index..last_index)

    index = index.clamp(first_index..last_index)

    if index < @selected # Moving left...
      selected.to_start_index
      nth(index).to_end_index
    elsif @selected < index # Moving right...
      selected.to_end_index
      nth(index).to_start_index
    end

    @selected = index
  end

  # Builds and returns a new, *index*-th buffer editor state.
  #
  # Should be overridden when the subclass desires a different
  # and/or index-dependent kind of buffer state for new editors.
  def new_substate_for(index)
    BufferEditorState.new
  end

  # Adds the given *state* before *index*. Returns *state*.
  def append(index : Int, state : BufferEditorState)
    @states.insert(index, state)

    state
  end

  # Appends a new buffer editor state (see `new_substate_for`)
  # at *index*. Returns the appended state.
  def append(index : Int)
    append(index, new_substate_for(index))
  end

  # Appends a new buffer editor state (see `new_substate_for`)
  # at the end.
  def append
    append(@states.size)
  end

  # **Destructive**: clears and drops the *index*-th editor
  # state. If the selected editor state was dropped, the
  # previous editor state is selected (if any; otherwise,
  # the next editor state is selected).
  def drop(index : Int)
    @states[index].clear
    @states.delete_at(index)
    to_prev
  end

  # **Destructive**: clears and drops the selected editor state.
  def drop
    drop(@selected)
  end

  # Selects the previous editor state. Does nothing if the
  # selected editor state is the first.
  def to_prev
    return if first_selected?

    to_nth(prev_index)
  end

  # Selects the next editor state. Does nothing if the selected
  # editor state is the last.
  def to_next
    return if last_selected?

    to_nth(next_index)
  end

  # Selects the first editor state.
  #
  # Does nothing if there are no editor states.
  def to_first
    return if empty?

    to_nth(first_index)

    selected.to_start_index
  end

  # Selects the last editor state.
  #
  # Does nothing if there are no editor states.
  def to_last
    return if empty?

    to_nth(last_index)

    selected.to_end_index
  end

  # Returns cursor index *as if the row was a single field*.
  def cursor
    cursor = selected.capture.cursor
    cursor += (first_index...@selected).sum { |n| nth(n).size + 1 }
    cursor
  end

  # **Destructive**: wipes out the content of all subordinate
  # editor states, and forgets about them.
  def clear
    @states.each &.clear
    @states.clear
  end

  # Splits the selected editor state in two at the cursor.
  #
  # If *backwards* is true, will then select the previous editor
  # state. Otherwise, the selected editor state will remain
  # unchanged.
  #
  # Adds a new empty editor state if cursor is at either end
  # of the selected editor state.
  #
  # Adds a new empty editor state if there are no editor states
  # regardless of *backwards*.
  def split(backwards : Bool)
    if empty?
      append
      return
    end

    before_cursor = selected.before_cursor
    after_cursor = selected.after_cursor

    appended = append(@selected + 1)
    appended.update! { after_cursor }
    selected.update! { before_cursor }

    return if backwards

    to_next
  end

  # Merges the current editor state with the previous or next editor
  # state, depending on whether *forward* is true or false.
  #
  # Does nothing if there are no editor states.
  def merge(forward : Bool)
    return if empty?
    return if !forward && first_selected?
    return if forward && last_selected?

    # Merge forward = Merge back from the next field.
    to_next if forward

    string = selected.capture.string

    # Drop the selected field and merge to the back.
    drop

    # Selected is now the previous field, because we have proven
    # that the selected field is not the first/last depending
    # on forward.
    selected.update! { |it| it + string }
  end
end

# A row of `BufferEditorView`s.
class BufferEditorRowView
  include SF::Drawable

  # Returns the position of this editor row view.
  property position = SF.vector2f(0, 0)

  # Returns whether this editor row view is active.
  property? active = false

  def initialize
    @views = [] of BufferEditorView
  end

  # Specifies the width of whitespace separating editor views
  # in this row.
  def wswidth
    6
  end

  # Specifies where the first editor view in this row should
  # be positioned.
  def origin
    position
  end

  # Calculates and returns the full size of this editor view row.
  def size
    return SF.vector2f(0, 0) if @views.empty?

    SF.vector2f(@views.sum(&.size.x) + wswidth * (@views.size - 1), @views.max_of(&.size.y))
  end

  # Builds and returns a new, *index*-th buffer editor view.
  #
  # Should be overridden when the subclass desires a different
  # and/or index-dependent kind of buffer view for new editors.
  def new_subview_for(index : Int)
    BufferEditorView.new
  end

  # Returns a new, *index*-th buffer editor view updated according
  # to the given buffer editor *instant*.
  #
  # Positions the new buffer editor view at `origin`.
  def new_subview_from(index : Int, instant : BufferEditorInstant)
    subview = new_subview_for(index)
    subview.active = false
    subview.position = origin
    subview.update(instant)
    subview
  end

  # Positions a consecutive pair of buffer editor views, *l* and *r*.
  def arrange_cons_pair(l : BufferEditorView, r : BufferEditorView)
    r.position = SF.vector2f(l.position.x + l.size.x + wswidth, l.position.y)
  end

  # Updates this editor row view from the given state *instant*.
  def update(instant : BufferEditorRowInstant)
    @views.clear

    states = instant.states
    return if states.empty?

    views = states.map_with_index { |state, index| new_subview_from(index, state) }
    views.each_cons_pair do |l, r|
      arrange_cons_pair(l, r)
    end

    views[instant.selected].active = true

    @views = views
  end

  # Updates this editor row view from the given *state*.
  def update(state : BufferEditorRowState)
    update(state.capture)
  end

  def draw(target, states)
    @views.each &.draw(target, states)
  end
end

# A row of `BufferEditor`s with the ability to move between
# editors when the selected editor's cursor is at either of
# its extremities.
#
# The selected editor can be sliced in half by pressing Tab.
# Tabbing at the beginning or end will result in an empty
# half before or after the cursor, correspondingly.
class BufferEditorRow < BufferEditorCollection
  include MonoBufferController(BufferEditorRowState, BufferEditorRowView)

  # Returns nil if when any missing method is called.
  private struct Ignore
    macro method_missing(call)
    end
  end

  def each_state(& : BufferEditorState ->)
    return if @state.empty?

    yield @state.selected
  end

  def handle(event : SF::Event::KeyPressed)
    s = @state.cursor_at_start? ? event.code : Ignore.new
    e = @state.cursor_at_end? ? event.code : Ignore.new

    case {event.code, s, e}
    when {.tab?, _, _}       then @state.split(backwards: event.shift)
    when {_, .left?, _}      then @state.to_prev
    when {_, _, .right?}     then @state.to_next
    when {_, .home?, _}      then @state.to_first
    when {_, _, .end?}       then @state.to_last
    when {_, .backspace?, _} then @state.merge(forward: false)
    when {_, _, .delete?}    then @state.merge(forward: true)
    else
      return super
    end

    refresh
  end
end
