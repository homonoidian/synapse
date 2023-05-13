# A time-ordered snapshot of `MenuItemState`.
#
# Allows clients to implement an undo/redo system independent
# of `MenuItemState`.
#
# Also allows clients to peek into `MenuItemState` at discrete time
# steps for change-awareness.
class MenuItemInstant < LabelInstant
  def initialize(instant : LabelInstant)
    initialize(instant.timestamp, instant.caption)
  end
end

# Logic and state for a menu item: a string description of the item.
class MenuItemState < LabelState
  def capture
    MenuItemInstant.new(super)
  end
end

# View for a menu item: a string description of the item and a character
# icon that illustrates the description.
class MenuItemView < LabelView
  include IRemixIconView

  # Holds the character used as the icon.
  property icon = Icon::GenericAdd

  def padding
    SF.vector2f(10, 3)
  end

  def origin
    super + SF.vector2f(icon_span_x, icon_font_size // 4)
  end

  def size
    super + SF.vector2f(icon_span_x, icon_font_size // 4)
  end

  def icon_color
    text_color
  end

  def text_color
    active? ? SF::Color.new(0xbb, 0xd3, 0xff) : SF::Color.new(0xCC, 0xCC, 0xCC)
  end

  def draw(target, states)
    super

    icon = icon_text
    icon.position = position + padding
    icon.draw(target, states)
  end
end
