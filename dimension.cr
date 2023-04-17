# Generic control logic for a dimension (e.g. row, column) of
# `State`s with one currently `selected` `State`.
abstract class DimensionState(State)
  def initialize
    @states = [] of State
    @selected = 0
  end

  # Builds and returns a new, *index*-th subordinate `State`.
  #
  # Must be implemented by the subclass dimension to specify
  # the desired (and optionally index-dependent) kind of new,
  # subordinate state.
  abstract def new_substate_for(index : Int) : State

  # Captures and returns an instant of this editor dimension.
  #
  # Useful for undo/redo.
  abstract def capture

  # Returns whether there are currently no editors in this
  # editor dimension.
  def empty?
    size.zero?
  end

  # Returns the amount of editors in this editor dimension.
  def size
    @states.size
  end

  # Returns the index of the first state.
  def first_index
    0
  end

  # Returns the index of the last state.
  def last_index
    @states.size - 1
  end

  # Clamps *index* in the bounds of this editor dimension.
  def clamp(index : Int)
    index.clamp(first_index..last_index)
  end

  # Returns the index of the previous state.
  def prev_index
    @selected - 1
  end

  # Returns the index of the next state.
  def next_index
    @selected + 1
  end

  # Returns the *n*-th state, or raises.
  def nth(n : Int)
    @states[n]
  end

  # Returns the selected state.
  def selected
    nth(@selected)
  end

  # Returns whether the cursor is at the beginning of the selected state.
  def cursor_at_start?
    return true if empty?

    selected.at_start_index?
  end

  # Returns whether the cursor is at the end of the selected state.
  def cursor_at_end?
    return true if empty?

    selected.at_end_index?
  end

  # Returns whether the first state is selected.
  def first_selected?
    @selected == first_index
  end

  # Returns whether the last state is selected.
  def last_selected?
    @selected == last_index
  end

  # Invoked after motion left happens from/to *state*.
  def after_moved_left(state : State)
  end

  # Invoked after motion right happens from/to *state*.
  def after_moved_right(state : State)
  end

  # Selects *index*-th state. Clamps *index* to the bounds of
  # the states in this dimension.
  #
  # Does nothing if there are no states.
  def to_nth(index : Int)
    @selected, prev = clamp(index), clamp(@selected)

    return if empty?

    if @selected < prev # Moving left...
      after_moved_left(nth(prev))
      after_moved_right(selected)
    elsif prev < @selected # Moving right...
      after_moved_right(nth(prev))
      after_moved_left(selected)
    end
  end

  # Adds the given *state* before *index*. Returns *state*.
  def append(index : Int, state : State) : State
    @states.insert(index, state)

    state
  end

  # Appends a subordinate state (see `new_substate_for`) at
  # *index*. Returns the appended state.
  def append(index : Int)
    append(index, new_substate_for(index))
  end

  # Appends a subordinate state *state* at *index*. Returns the
  # appended state
  def append(state : State)
    append(last_index + 1, state)
  end

  # Appends a subordinate state (see `new_substate_for`) at
  # the end.
  def append
    append(last_index + 1)
  end

  # Selects the previous state. Does nothing if the selected
  # state is the first.
  def to_prev
    return if first_selected?

    to_nth(prev_index)
  end

  # Selects the next state. Does nothing if the selected state
  # is the last.
  def to_next
    return if last_selected?

    to_nth(next_index)
  end

  # Selects the first state.
  #
  # Does nothing if there are no states.
  def to_first
    return if empty?

    to_nth(first_index)

    after_moved_left(selected)
  end

  # Selects the last state.
  #
  # Does nothing if there are no states.
  def to_last
    return if empty?

    to_nth(last_index)

    after_moved_right(selected)
  end

  # **Destructive**: clears and drops the *index*-th state. If
  # the selected state was dropped, the previous state is selected
  # (if any; otherwise, the next available state is selected).
  def drop(index : Int)
    @states[index].clear
    @states.delete_at(index)
    to_prev
  end

  # **Destructive**: clears and drops the selected state.
  def drop
    drop(@selected)
  end

  # **Destructive**: wipes out the content of all subordinate
  # states, and forgets about them.
  def clear
    @states.each &.clear
    @states.clear
    @selected = 0
  end

  # Splits the selected state in two at the cursor.
  #
  # If *backwards* is true, will then select the previous editor
  # state. Otherwise, the selected state will remain unchanged.
  #
  # Adds a new empty state if cursor is at either end of the
  # selected state.
  #
  # Adds a new empty state if there are no states regardless
  # of *backwards*.
  def split(backwards : Bool)
    if empty?
      append
      return
    end

    appended = append(@selected + 1)

    splitdist(selected, appended)

    return if backwards

    to_next
  end

  # Distributes the content of *left* between *left* and *right*
  # according to the rules of this dimension.
  #
  # *left* comes before *right* but the definition of "before"
  # depends on the subclass.
  def splitdist(left : State, right : State)
  end

  # Merges the current state with the previous or next editor
  # state, depending on whether *forward* is true or false.
  #
  # Does nothing if there are no states.
  def merge(forward : Bool)
    return if empty?
    return if !forward && first_selected?
    return if forward && last_selected?

    # Merge forward = Merge back from the next field.
    to_next if forward

    merge!
  end

  # Merges the current state into the state behind.
  #
  # The default implementation has nothing to do with actually
  # *merging*: it simply drops the current state.
  #
  # However, implementors may choose to do content-defined
  # merging as appropriate.
  #
  # If you are a user, consider `merge(forward : Bool)` as it
  # is much more user-friendly. This method is allowed to raise
  # e.g. when there are no states, or when trying to
  # merge behind the first state.
  def merge!
    drop
  end
end

# Generic view code for a dimension (e.g. row, column) of
# subordinate `View`s with one currently active view.
#
# Designed to work together with `DimensionState` only. Updates
# the displayed views from `DimensionState`.
#
# Activity of `DimensionView` specifies whether the active view
# should be active *on the next update*.
#
# * `Instant` is the instant type of the displayed `DimensionState`.
#
# * `SubInstant` is the instant type of the subordinate state
#    of `DimensionState`.
abstract class DimensionView(View, Instant, SubInstant)
  include SF::Drawable

  # Returns the position of this editor row view.
  property position = SF.vector2f(0, 0)

  # Returns whether this editor row view is active.
  property? active = false

  def initialize
    @views = [] of View
  end

  # Calculates and returns the full size of this dimension view.
  abstract def size : SF::Vector2f

  # Builds and returns a new, *index*-th subordinate `View`.
  #
  # Must be implemented by the subclass dimension to specify
  # the desired (and optionally index-dependent) kind of new,
  # subordinate view.
  abstract def new_subview_for(index : Int) : View

  # Updates the positions of a consecutive pair of subordinate
  # views, *l* and *r*.
  abstract def arrange_cons_pair(left : View, right : View)

  # Specifies the position of the first view in this dimension.
  def origin
    position
  end

  # Returns a new, *index*-th subordinate view updated according
  # to the given *instant*.
  #
  # Positions the new subordinate view at `origin`.
  def new_subview_from(index : Int, instant : SubInstant, selected : Int)
    subview = new_subview_for(index)
    subview.active = active? && index == selected
    subview.position = origin
    subview.update(instant)
    subview
  end

  # Updates this editor row view from the given state *instant*.
  def update(instant : Instant)
    @views.clear

    states = instant.states
    return if states.empty?

    views = states.map_with_index { |state, index| new_subview_from(index, state, instant.selected) }
    views.each_cons_pair { |l, r| arrange_cons_pair(l, r) }

    # To do arrange() subviews must be updated(). However, after
    # arrange() subviews' positions have changed, and on such a
    # change they want another update().
    #
    # This leads to us having to call update() twice, which
    # shouldn't be that expensive but still looks quite smelly.
    views.zip(states) { |view, state| view.update(state) }

    @views = views
  end

  # Updates this editor row view from the given *state*.
  def update(state)
    update(state.capture)
  end

  def draw(target, states)
    @views.each &.draw(target, states)
  end
end
