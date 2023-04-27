# The state of a rule editor. See subclasses for more specific info.
class RuleEditorState < BufferEditorColumnState
end

# The view of a rule editor. See subclasses for more specific info.
#
# Drawing happens in the following order:
#
# * `describe` -- "layer 0" (bottom layer) -- is drawn
# * `decorate` -- "layer 1" -- is drawn
# * subviews are drawn
class RuleEditorView < BufferEditorColumnView
  # Whether to draw the shadow under this rule editor view.
  #
  # Shadow is semi-transparent and *isn't necessarily inscribed
  # in the bounds of this view*.
  property? shadow = false

  def wsheight
    0
  end

  # Returns the minimum size (width, height) for this rule editor.
  def min_size
    SF.vector2f(25 * 6, 0)
  end

  # Specifies the background color of this editor as a whole.
  def background_color
    SF::Color.new(0x31, 0x31, 0x31)
  end

  # Specifies the color of the outline of this editor.
  def outline_color
    active? ? SF::Color.new(0x43, 0x51, 0x80) : SF::Color.new(0x3f, 0x3f, 0x3f)
  end

  # Specifies the color of this editor's shadow.
  def shadow_color
    SF::Color.new(0xff, 0xff, 0xff, 0x11)
  end

  # Specifies the *outset* of this shadow, outset being the
  # distance between the shadow's bottom right corner and
  # bounding rectangle's bottom right corner.
  def shadow_outset
    SF.vector2f(9, 7)
  end

  # Draws the shadow for this view. By default draws a rectangular
  # shadow based on the bounds of this view, which may or may not
  # be appropriate.
  def draw_shadow(target, states)
    shadow_rect = SF::RectangleShape.new
    shadow_rect.position = position
    shadow_rect.size = size + shadow_outset
    shadow_rect.fill_color = shadow_color
    shadow_rect.draw(target, states)
  end

  # Layer 0: draws background-ish stuff.
  #
  # `super` method must be invoked at the very beginning.
  def describe(target, states)
    return unless shadow?

    draw_shadow(target, states)
  end

  # Layer 1: draws decorations.
  #
  # `super` method should be invoked when appropriate, but
  # generally at the very end.
  def decorate(target, states)
  end

  def draw(target, states)
    describe(target, states)
    decorate(target, states)

    super
  end
end

module RuleEditorHandler
  include Draggable(RuleEditorState)

  def lift
    @view.shadow = true
  end

  def drop
    @view.shadow = false
  end
end
