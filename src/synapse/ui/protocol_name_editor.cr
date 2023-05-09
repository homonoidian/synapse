# State for a protocol name editor, which is used, well, to
# edit a protocol's name.
class ProtocolNameEditorState < InputFieldState
end

# View for a protocol name editor.
class ProtocolNameEditorView < InputFieldView
  def font
    FONT_UI
  end

  def font_size
    24
  end

  def line_spacing
    1.0
  end

  def beam_margin
    SF.vector2f(0, super.y)
  end

  def beam_size(cur : SF::Vector2, nxt : SF::Vector2)
    SF.vector2f(1, line_height)
  end

  def outline_color
    active? ? SF::Color.new(0x43, 0x51, 0x80) : SF::Color.new(0x3f, 0x3f, 0x3f)
  end

  def beam_color
    text_color
  end

  def underline?
    false
  end
end
