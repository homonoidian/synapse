# Represents the state for input fields used to enter a rule keyword.
class KeywordInputState < InputFieldState
  def insertable?(printable : String)
    super && !(' '.in?(printable) || '\t'.in?(printable))
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
