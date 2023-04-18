# Rule code row state.
#
# Rule code row contains one and only one buffer editor: the
# rule code buffer editor.
class RuleCodeRowState < BufferEditorRowState
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
    SF.vector2f(8, 8)
  end

  # Specifies the vertical padding (content inset) for top,
  # bottom sides of this view.
  def py
    SF.vector2f(4, 6)
  end

  def origin
    position + SF.vector2f(px.x, py.x)
  end

  def size
    super + SF.vector2f(px.x + px.y, py.x + py.y)
  end
end
