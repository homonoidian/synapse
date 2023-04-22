# Heartbeat rule header state. Allows the user to optionally
# enter the period of the heartbeat.
class HeartbeatRuleHeaderState < KeywordRuleHeaderState
  def min_size
    1 # "heartbeat" dummy input
  end

  def max_size
    2 # "heartbeat" dummy input + period input
  end

  def first_index
    1 # after the dummy editor
  end

  def column_start_index
    0 # but account everyone when counting column
  end

  def merge(forward : Bool)
    # Superclass does not allow to remove the period input
    # because it is the first. Fix that.
    #
    # Also, knowing that there is only ever going to be one
    # input, do not spend time on all the complexities and
    # simply drop the field.
    return if empty? || !selected.empty?

    merge!
  end

  def merge!
    drop
  end

  def new_substate_for(index : Int)
    index == 0 ? HeartbeatInputState.new : PeriodInputState.new
  end
end

# Heartbeat rule header view.
#
# Displays the dummy heartbeat input and, optionally, the period
# of the heartbeat.
class HeartbeatRuleHeaderView < KeywordRuleHeaderView
  def new_subview_for(index : Int)
    index == 0 ? HeartbeatInputView.new : PeriodInputView.new
  end

  def origin
    super + SF.vector2f(icon_span_x, 0)
  end

  def size
    super + SF.vector2f(icon_span_x, 0)
  end

  # Specifies the character used as the icon in the header.
  def icon_char
    "♥"
  end

  # Specifies how many pixels should be allocated to the icon
  # character at the top left corner.
  def icon_span_x
    10
  end

  # Specifies the font which should be used to render the
  # icon character.
  def icon_font
    FONT
  end

  # Returns the color which should be used to paint the icon.
  def icon_color
    SF::Color.new(0xeb, 0x7a, 0x8e)
  end

  def draw(target, states)
    super

    icon = SF::Text.new(icon_char, icon_font, 11)
    icon.position = position + padding # ???
    icon.fill_color = icon_color
    icon.draw(target, states)
  end
end
