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

  def to_rule_signature
    period = @states[1]?.as?(PeriodInputState).try &.string

    return HeartbeatRuleSignature.new(period: nil) unless period

    # FIXME: handle to_i failure?
    if period_s = period.rchop?("ms")
      period_span = period_s.to_i.milliseconds
    elsif period_s = period.rchop?("s")
      period_span = period_s.to_i.seconds
    else
      period_span = nil # FIXME: this should be an error arm!
    end

    HeartbeatRuleSignature.new(period_span)
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
  include IRemixIconView

  def new_subview_for(index : Int)
    index == 0 ? HeartbeatInputView.new : PeriodInputView.new
  end

  def origin
    super + SF.vector2f(icon_span_x, 0)
  end

  def size
    super + SF.vector2f(icon_span_x, 0)
  end

  def icon
    Icon::HeartbeatRule
  end

  def icon_span_x
    16
  end

  def icon_font_size
    11
  end

  def icon_color
    SF::Color.new(0xeb, 0x7a, 0x8e)
  end

  def draw(target, states)
    super

    icon = icon_text
    icon.position = position + padding # ???
    icon.draw(target, states)
  end
end
