# An object that can be focused by `Lens`.
module Inspectable
  # Returns whether this inspectable can be focused.
  def can_be_focused?
    true
  end

  # Returns whether this inspectable can be blurred.
  def can_be_blurred?
    true
  end

  # Called when this inspectable is focused.
  def focus
  end

  # Called when this inspectable is blurred.
  def blur
  end

  # Handles *event* forwarded by the lens when this inspectable is focused.
  def handle(event : SF::Event)
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

  def aiming_at?(cls : T.class) forall T
    @object.is_a?(T)
  end

  def forward(event : SF::Event)
    @object.handle(event)
  end

  def each(&)
    yield @object
  end
end
