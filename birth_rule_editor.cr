# State for a birth rule editor, which consists of a single
# code buffer editor.
class BirthRuleEditorState < BufferEditorColumnState
  def min_size
    1 # Code buffer
  end

  def max_size
    1 # Code buffer
  end

  def new_substate_for(index : Int)
    RuleCodeRowState.new
  end
end

# View for a birth rule editor.
class BirthRuleEditorView < BufferEditorColumnView
  def wsheight
    0
  end

  # Returns the caption displayed above the rule.
  def caption
    "✮ born"
  end

  # Specifies the amount of vertical space to allocate for
  # the caption text.
  def caption_space_y
    16
  end

  # Specifies the maximum amount of characters in the rule
  # caption. The rest of the caption will be truncated with
  # ellipsis `…`.
  def caption_max_chars
    12
  end

  # Specifies the color of the caption.
  def caption_color
    active? ? SF::Color.new(0xE0, 0xE0, 0xE0) : SF::Color.new(0xBD, 0xBD, 0xBD)
  end

  def padding
    SF.vector2f(4, 4)
  end

  def origin
    super + SF.vector2f(0, caption_space_y) + padding
  end

  def snapstep
    SF.vector2f(12, 11)
  end

  def min_size
    SF.vector2f(25 * 6, 0)
  end

  def size
    size = super + SF.vector2f(0, caption_space_y) + padding*2
    size.max(min_size)
  end

  # Specifies the background color of this editor as a whole.
  def background_color
    SF::Color.new(0x31, 0x31, 0x31)
  end

  # Specifies the color of the outline of this editor.
  def outline_color
    active? ? SF::Color.new(0x43, 0x51, 0x80) : SF::Color.new(0x3f, 0x3f, 0x3f)
  end

  def draw(target, states)
    #
    # Draw background rectangle.
    #
    bgrect = SF::RectangleShape.new
    bgrect.position = origin - padding
    bgrect.size = size - (origin - position - padding)
    bgrect.fill_color = background_color
    bgrect.outline_color = outline_color
    bgrect.outline_thickness = 2
    bgrect.draw(target, states)

    #
    # Create caption.
    #
    cap = SF::Text.new(caption.trunc(caption_max_chars), FONT_BOLD, 11)
    cap.position = position + SF.vector2f(padding.x, 0)
    cap.fill_color = caption_color

    #
    # Draw caption background followed by caption.
    #
    capbg = SF::RectangleShape.new
    capbg.position = cap.position - SF.vector2f(bgrect.outline_thickness, bgrect.outline_thickness) - SF.vector2f(padding.x, 0)
    capbg.fill_color = bgrect.outline_color
    capbg.size = SF.vector2f(Math.max(cap.size.x, min_size.x/2), cap.size.y) + SF.vector2f(0, bgrect.outline_thickness*2)

    capbg.draw(target, states)
    cap.draw(target, states)

    super
  end
end

# Birth rule editor allows to create and edit a birth rule.
#
# Birth rules are rules that are expressed once when the receiver
# cell is born. They are very similar to initializers in OOP.
class BirthRuleEditor
  include MonoBufferController(BirthRuleEditorState, BirthRuleEditorView)

  include BufferEditorHandler
  include BufferEditorRowHandler
  include BufferEditorColumnHandler
end
