# Regex that matches a valid Lua identifier.
LUA_ID_REGEX = /^[_a-zA-Z]\w*$/

# Represents the state for input fields used to enter a rule keyword.
class KeywordInputState < InputFieldState
  def insertable?(printable : String)
    instant = capture
    keyword = instant.string.insert(instant.cursor, printable)
    keyword.matches?(LUA_ID_REGEX)
  end
end

# View for input fields used to enter a rule keyword.
class KeywordInputView < InputFieldView
  def font
    FONT_ITALIC
  end

  def underline_color
    SF::Color.new(0xbb, 0x88, 0xdc)
  end

  def beam_color
    SF::Color.new(0xf1, 0xd9, 0xff)
  end

  def text_color
    SF::Color.new(0xbb, 0x88, 0xdc)
  end
end
