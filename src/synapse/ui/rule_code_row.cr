# Rule code row state.
#
# Rule code row contains one and only one buffer editor: the
# rule code buffer editor.
class RuleCodeRowState < BufferEditorRowState
  def string
    editor = @states[0].as(BufferEditorState)
    editor.string
  end

  def min_size
    1
  end

  def max_size
    1
  end
end

# The appearance of a rule code row, which is a row of one and
# only one buffer editor with some padding.
class RuleCodeRowView < BufferEditorRowView
  # Specifies the horizontal padding (content inset) for left,
  # right sides of this view.
  def px
    SF.vector2f(6, 8)
  end

  # Specifies the vertical padding (content inset) for top,
  # bottom sides of this view.
  def py
    SF.vector2f(4, 6)
  end

  # Returns padding X, Y vector in the top-left corner.
  def padding_tl
    SF.vector2f(px.x, py.x)
  end

  # Returns padding X, Y vector in the bottom-right corner.
  def padding_br
    SF.vector2f(px.y, py.y)
  end

  def origin
    position + padding_tl
  end

  def size
    super + padding_tl + padding_br
  end
end
