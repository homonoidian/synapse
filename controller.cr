# Returns nil if when any missing method is called.
struct Ignore
  macro method_missing(call)
  end
end

# A generic controller implementing abstract focus facilities
# and noop SFML event handling.
module IController
  include SF::Drawable

  # Returns whether this controller is focused.
  getter? focused = false

  # Returns whether *point* is in the bounds of this controller's view.
  def includes?(point : SF::Vector2)
    false
  end

  # Returns whether this controller can accept focus.
  def can_focus?
    true
  end

  # Returns whether this controller can release focus.
  def can_blur?
    true
  end

  # Accepts focus.
  def focus
    @focused = true

    refresh
  end

  # Releases focus.
  def blur
    @focused = false

    refresh
  end

  # **Destructive**: wipes out the data, states, and views in
  # this controller. How much destructive it is is defined by
  # the implementor.
  abstract def clear

  # Updates the view according to the state.
  abstract def refresh

  # Handles the given *event* regardless of focus.
  abstract def handle!(event : SF::Event)

  # Handles the given SFML *event* if this controller is focused.
  def handle(event : SF::Event)
    return unless focused?

    handle!(event)
  end
end

# A single view, single model controller. May or may not work
# for you. Remember you can always include `IController` as
# an alternative.
#
# Requires the following:
#
# * `State#clear` to clear the state.
# * `View#active?`, `View#active=` to query/set whether the view is active.
# * `View#update(state : State)` to update the view from the given state.
# * `View` must be an `SFML::Drawable`.
# * Includer must implement `handle!(State, event : SF::Event)`.
module MonoBufferController(State, View)
  include IController

  def initialize(@state : State, @view : View)
    @focused = @view.active?

    refresh
  end

  def includes?(point : SF::Vector2)
    @view.includes?(point)
  end

  def refresh
    @view.update(@state)
  end

  def focus
    @view.active = true

    super
  end

  def blur
    @view.active = false

    super
  end

  def clear
    @state.clear

    refresh
  end

  def handle!(event : SF::Event)
    handle!(@state, event)
  end

  def draw(target, states)
    @view.draw(target, states)
  end
end
