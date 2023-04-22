# The state of a rule editor. See subclasses for more specific info.
class RuleEditorState < BufferEditorColumnState
end

# The view of a rule editor. See subclasses for more specific info.
class RuleEditorView < BufferEditorColumnView
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
end
