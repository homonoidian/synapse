# A time-ordered snapshot of `LabelState`.
#
# Allows clients to implement an undo/redo system independent
# of `LabelState`.
#
# Also allows clients to peek into `LabelState` at discrete time
# steps for change-awareness.
record LabelInstant, timestamp : Int64, caption : String do
  # Returns whether two label instants are equal.
  #
  # **Important**: timestamps are not compared.
  def_equals caption
end

# State for a label: a component that displays a string.
class LabelState
  @caption = ""

  # Updates the caption of this label to *caption*.
  def update(@caption : String)
  end

  # Captures and returns an instant of this label.
  def capture
    LabelInstant.new(Time.local.to_unix, @caption)
  end
end

# View for a label: a component that displays a string.
class LabelView
  include IView

  property position = SF.vector2f(0, 0)

  def initialize
    @text = SF::Text.new("", font, font_size)
  end

  def font
    FONT_BOLD
  end

  def font_size
    11
  end

  def padding
    SF.vector2f(0, 0)
  end

  def origin
    position + padding + SF.vector2f(0, -@text.size.y//8)
  end

  def size
    @text.size + padding*2
  end

  def text_color
    SF::Color::White
  end

  def background_color
    SF::Color::Transparent
  end

  def update(instant : LabelInstant)
    @text.string = instant.caption
  end

  def draw(target, states)
    unless background_color.a.zero?
      bgrect = SF::RectangleShape.new
      bgrect.fill_color = background_color
      bgrect.position = position
      bgrect.size = size
      bgrect.draw(target, states)
    end

    @text.position = origin
    @text.fill_color = text_color
    @text.draw(target, states)
  end
end
