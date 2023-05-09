abstract struct DragEvent
end

record DragEvent::Grabbed < DragEvent
record DragEvent::Dragged < DragEvent
record DragEvent::Dropped < DragEvent

# Naïve draggability support for `IController`.
#
# * When mouse button is pressed, grip is acquired.
# * When mouse button is released, grip is released.
# * When mouse is moved, translates the includer's view.
#
# `DragEvent`s (grabbed, dragged, dropped) are sent to the
# `motion` stream, which you can listen to for e.g. drag-
# specific actions.
module Draggable(State)
  # The stream of positions of the underlying view, when dragged.
  getter dragging = Stream(DragEvent).new

  @grip : SF::Vector2f?

  # Acquires *grip* at position.
  def grab(@grip)
    dragging.emit(DragEvent::Grabbed.new)
  end

  # Acquires grip.
  def handle!(editor : State, event : SF::Event::MouseButtonPressed)
    grab SF.vector2f(event.x, event.y)
  end

  # Releases grip.
  def handle!(editor : State, event : SF::Event::MouseButtonReleased)
    return unless @grip

    @grip = nil

    dragging.emit(DragEvent::Dropped.new)
  end

  # Translates the underlying view to where the mouse is, and
  # updates it.
  def handle!(editor : State, event : SF::Event::MouseMoved)
    return unless handle = @grip

    mouse = SF.vector2f(event.x, event.y)
    delta = mouse - handle

    @view.position += delta
    @grip = mouse

    dragging.emit(DragEvent::Dragged.new)

    refresh
  end
end
