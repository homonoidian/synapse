# State for the period input field used in `HeartbeatRuleHeaderState`.
class PeriodInputState < ParamInputState
  def insertable?(printable : String)
    !printable.matches?(/\s/)
  end
end

# View for the period input field used in `HeartbeatRuleHeaderView`.
class PeriodInputView < InputFieldView
end
