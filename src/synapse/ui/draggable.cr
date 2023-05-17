# Includers can be used as draggable objects in `DragHandler`.
module IDraggable
  # Performs necessary routine after this object is lifted.
  def lifted
  end

  # Performs necessary routine for when this object is being dragged.
  #
  # *delta* is the change (in pixels) of mouse position between two
  # `dragged` calls or between a `lifted` and the first `dragged` calls.
  def dragged(delta : Vector2)
  end

  # Performs necessary routine after this object is dropped.
  def dropped
  end
end
