# Imcluders are views.
module IView
  include SF::Drawable

  # Determines whether this view is active.
  property? active = false

  # Returns the position of this view.
  abstract def position

  # Moves this view to *position*.
  abstract def position=(position : SF::Vector2)

  # Returns the size of this view.
  abstract def size

  # Returns whether *point* lies in the bounds of this view.
  def includes?(point : SF::Vector2)
    size = self.size

    position.x <= point.x <= position.x + size.x &&
      position.y <= point.y <= position.y + size.y
  end
end
