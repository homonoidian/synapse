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
