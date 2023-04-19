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
    SF::Color.new(0xcf, 0x89, 0x9f)
  end

  def beam_color
    SF::Color.new(0xfa, 0xb1, 0xc7)
  end

  def text_color
    SF::Color.new(0xcf, 0x89, 0x9f)
  end
end
