# State for a keyword rule editor, which consists of a keyword
# rule header (keyword and parameters for the rule), followed
# by a code row which holds a single code buffer editor.
class KeywordRuleEditorState < RuleEditorState
  def min_size
    1 # Rule header
  end

  def max_size
    2 # Rule header + rule code
  end

  def new_substate_for(index : Int)
    {KeywordRuleHeaderState, RuleCodeRowState}[index].new
  end
end

# View for a keyword rule editor. Has some background and outline.
# The color of the latter depends on whether the view is active.
class KeywordRuleEditorView < RuleEditorView
  def snapstep
    SF.vector2f(6, @views.size > 1 ? 11 : 0)
  end

  def size
    super.max(min_size)
  end

  def new_subview_for(index : Int)
    {KeywordRuleHeaderView, RuleCodeRowView}[index].new
  end

  # Specifies the background color for the header `RuleHeaderView`.
  def header_color
    SF::Color.new(0x3f, 0x3f, 0x3f)
  end

  # Invoked after editor background and header background are
  # drawn, but before editor content is drawn.
  def decorate(target, states)
    return super unless active?

    base_color = SF::Color.new(0x36, 0x8d, 0x68)

    activity_sign = SF::RectangleShape.new
    activity_sign.size = SF.vector2f(5, 5)
    activity_sign.position = selected.position + SF.vector2f(-10, 7.5)
    activity_sign.fill_color = base_color
    activity_sign.draw(target, states)

    super
  end

  def describe(target, states)
    super

    #
    # Draw background rectangle.
    #
    bgrect = SF::RectangleShape.new
    bgrect.position = position
    bgrect.size = size
    bgrect.fill_color = background_color
    bgrect.outline_color = outline_color
    bgrect.outline_thickness = 2
    bgrect.draw(target, states)

    if @views.size > 1
      #
      # Draw header background when there is code for clearer
      # seperation between them.
      #
      headbg = SF::RectangleShape.new
      headbg.position = SF.vector2f(position.x, position.y)
      headbg.size = SF.vector2f(size.x, @views[0].size.y)
      headbg.fill_color = header_color
      headbg.draw(target, states)
    end
  end
end

# Provides the includer with a suite of `handle!` methods for
# controlling a `KeywordRuleEditorState`.
module KeywordRuleEditorHandler
  # Handles the given *event* assuming *header* is selected
  # in *editor*.
  def handle!(
    editor : KeywordRuleEditorState,
    header : KeywordRuleHeaderState,
    event : SF::Event::KeyPressed
  )
    case event.code
    when .space?
      # Since spaces cannot be part of a keyword or a parameter,
      # we can use them as a more convenient alternative to Tab.
      header.split(backwards: event.shift)
    when .enter?, .down?
      # Pressing Enter or down arrow will move to the code field,
      # creating it if necessary.
      editor.append if editor.size == 1
      editor.to_next_with_column(header.column)
    else
      handle!(header, event)
      return
    end

    refresh
  end

  # Handles the given *event* assuming *code_row* is selected
  # in *editor*.
  def handle!(
    editor : KeywordRuleEditorState,
    code_row : RuleCodeRowState,
    event : SF::Event::KeyPressed
  )
    code = code_row.selected

    case event.code
    when .backspace?
      # Pressing Backspace at the beginning of the code editor,
      # if there is no code in it, will remove the row that
      # holds the code editor.
      unless code.at_start_index? && code.empty?
        handle!(code_row, event)
        return
      end
      editor.drop
    when .up?
      # Pressing Up arrow at the first line of the code editor
      # will select the rule header.
      unless code.at_first_line?
        handle!(code_row, event)
        return
      end
      editor.to_prev_with_column(code_row.column)
    else
      handle!(code, event)
      return
    end

    refresh
  end

  # Handles the given *event* regardless of focus.
  def handle!(editor : KeywordRuleEditorState, selected, event)
    handle!(selected, event)
  end

  # :ditto:
  def handle!(editor : KeywordRuleEditorState, event : SF::Event)
    return if editor.empty?

    selected = editor.selected

    begin
      handle!(editor, selected, event)
    rescue DimensionOverflowException | DimensionUnderflowException
      handle!(selected, event)
    end
  end
end

# Keyword rule editor allows to create and edit a keyword rule.
#
# Keyword rules are rules whose expression depends on whether an
# incoming message's keyword matches the keyword of the rule.
class KeywordRuleEditor
  include MonoBufferController(KeywordRuleEditorState, KeywordRuleEditorView)

  include BufferEditorHandler
  include BufferEditorRowHandler
  include KeywordRuleEditorHandler
  include CellEditorEntity
  include RuleEditorHandler
end
