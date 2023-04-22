# Rule header state. See subclasses for more specific descriptions.
abstract class RuleHeaderState < InputFieldRowState
  def min_size
    1
  end
end

# The base appearance of rule headers. See subclasses for more
# specific descriptions.
abstract class RuleHeaderView < InputFieldRowView
  # Specifies the padding, which stands for how inset the
  # subviews are in the bounds of this view.
  def padding
    SF.vector2f(6, 2)
  end

  def origin
    position + padding
  end

  def size : SF::Vector2f
    super + padding * 2
  end
end
