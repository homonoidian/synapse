# Includer views have a font/character icon *somewhere*.
#
# Where the icon is drawn is up to the includer view. This
# module only standardizes how the icon is defined, and can
# build and return an `SF::Text` object from the definition.
module IIconView
  # Specifies the character used as the icon.
  abstract def icon

  # Specifies the font used to draw the icon.
  abstract def icon_font

  # Specifies the font size of the icon.
  abstract def icon_font_size

  # Specifies the amount of horizontal space that needs to be
  # allocated for the icon.
  abstract def icon_span_x

  # Specifies the color which should be used to paint the icon.
  abstract def icon_color

  # Builds and returns an `SF::Text` object corresponding to
  # the icon. You will have to position the text yourself.
  def icon_text : SF::Text
    text = SF::Text.new(icon, icon_font, icon_font_size)
    text.fill_color = icon_color
    text
  end
end

REMIX_FONT = SF::Font.from_memory({{read_file("./fonts/ui/remixicon.ttf")}}.to_slice)
REMIX_FONT.get_texture(13).smooth = false

# Semantic icon character store.
module Icon
  Protocol      = "\uEAD4"
  BirthRule     = "\uF35B"
  GenericAdd    = "\uECC8"
  KeywordRule   = "\uF106"
  HeartbeatRule = "\uEE0A"
  Paused        = "\uEFD5"
end

# Implements `icon_font` and a few other methods from `IIconView`
# for using Remix as the icon font.
module IRemixIconView
  include IIconView

  def icon_font
    REMIX_FONT
  end

  def icon_font_size
    13
  end

  def icon_span_x
    18
  end
end
