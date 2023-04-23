# Naïve draggability support for `IController`.
#
# * When mouse button is pressed, grip is acquired.
# * When mouse button is released, grip is released.
# * When mouse is moved, translates the includer's view.
module Draggable(State)
  @grip : SF::Vector2f?

  # Invoked when dragging starts.
  #
  # Noop by default.
  def on_drag_start
  end

  # Invoked when dragging ends.
  #
  # Noop by default.
  def on_drag_end
  end

  # Acquires grip.
  def handle!(editor : State, event : SF::Event::MouseButtonPressed)
    @grip = SF.vector2f(event.x, event.y)

    on_drag_start
  end

  # Releases grip.
  def handle!(editor : State, event : SF::Event::MouseButtonReleased)
    return unless @grip

    @grip = nil

    on_drag_end
  end

  # Translates the underlying view to where the mouse is, and
  # updates it.
  def handle!(editor : State, event : SF::Event::MouseMoved)
    return unless handle = @grip

    mouse = SF.vector2f(event.x, event.y)
    delta = mouse - handle

    @view.position += delta
    @grip = mouse

    refresh
  end
end
