# State for the dummy input used in `HeartbeatRuleHeaderState`
# to signify the rule is a heartbeat rule.
#
# Technically can still be used as an editable input field.
# Whether to prevent that (or not!) is up to the creator.
class HeartbeatInputState < InputFieldState
  def initialize
    super("heartbeat")
  end
end

# View for the dummy input used in `HeartbeatRuleHeaderView`
# to signify the rule is a heartbeat rule.
#
# Technically can still be used as an editable input field.
# Whether to prevent that (or not!) is up to the creator.
class HeartbeatInputView < InputFieldView
  def font
    FONT_BOLD
  end

  def text_color
    SF::Color.new(0xeb, 0x7a, 0x8e)
  end
end
