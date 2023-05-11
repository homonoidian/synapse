# An object that can be focused by `Lens`.
module Inspectable
  # Returns a view (possibly derived from *view* or exactly *view*)
  # that encloses this inspectable, or includes this inspectable.
  #
  # But really, what you do here doesn't matter as long as you return
  # a view.
  abstract def into(view : SF::View) : SF::View

  # Returns whether this inspectable can be focused.
  def can_be_focused?
    true
  end

  # Returns whether this inspectable can be blurred.
  def can_be_blurred?
    true
  end

  # Invoked when this inspectable is focused.
  def focus
  end

  # Invoked when this inspectable is blurred.
  def blur
  end
end

# A lens is an object that can aim at `Inspectable`s, negotiate re-aming
# from one `Inspectable` to another and to void, forward events to the
# inspectable it's aiming at, and so on.
abstract struct Lens
  # Yields a new `Lens` object which is aimed at the given inspectable
  # *object* if the currently focused object wants to blur.
  def focus(object : Inspectable, & : Lens ->)
    yield Lens::Focused.new(object)
  end

  # :ditto:
  def focus(object : Nil, & : Lens ->)
    yield Lens::Blurred.new
  end

  # Returns whether this lens is aimed at the given *object*.
  def aiming_at?(object)
    false
  end

  # Configures and returns the given *view*, making sure that whatever
  # this lens is aimed at fits or is at least included in it.
  def configure(view : SF::View) : SF::View
    view
  end

  # Forwards the given *event* to whatever this lens is aimed at.
  def forward(event : SF::Event)
  end

  # Yields the focused object(s).
  def each(&)
  end
end

# Represents a blurred lens -- a lens pointing at nothing (nil).
struct Lens::Blurred < Lens
  def focus(object : Inspectable, &block : Lens ->)
    if object.can_be_focused?
      object.focus
    end

    super { |lens| yield lens }
  end

  def aiming_at?(object : Nil)
    true
  end
end

# Represents a lens that is aimed at some `Inspectable` object.
struct Lens::Focused < Lens
  def initialize(@object : Inspectable)
  end

  def focus(object : Inspectable, &block : Lens ->)
    if aiming_at?(object)
      yield self
      return
    end

    return unless @object.can_be_blurred? && object.can_be_focused?

    @object.blur
    object.focus

    super { |lens| yield lens }
  end

  def focus(object : Nil, &block : Lens ->)
    return unless @object.can_be_blurred?

    @object.blur

    super { |lens| yield lens }
  end

  def aiming_at?(object : Inspectable)
    @object === object
  end

  def configure(view : SF::View) : SF::View
    @object.into(view)
  end

  def forward(event : SF::Event)
    @object.handle(event)
  end

  def each(&)
    yield @object
  end
end
