# A rule agent owns a `Rule` -- sort of, at least it can construct it
# from whatever data it has access to.
#
# Rule agents react to vesicles and work to support their host `Cell`'s
# lifecycle: they handle the host's birth and heartbeat, two of the most
# important lifecycle events.
abstract class RuleAgent < Agent
  # Returns the `Rule` corresponding to this agent.
  def rule
    editor.to_rule
  end

  # Returns whether this rule agent's `Rule` matches the *other* `Rule`.
  def matches?(other : Rule)
    rule.matches?(other)
  end

  def copy(*, in browser : AgentBrowser)
    copy = browser.summon(self.class, coords: mid)
    copy.drain(editor)
    copy
  end

  def copy(protoplasm : Protoplasm)
    copy = self.class.new(protoplasm)
    copy.mid = mid
    copy.drain(editor)
    copy.summon
    copy
  end

  # Copies this rule agent in the given *browser*, then connects it to
  # a *protocol* agent.
  def copy(*, under protocol : ProtocolAgent, in browser : AgentBrowser)
    copy = copy(in: browser)
    copy.mid = protocol.mid
    copy.connect(to: protocol, in: browser)
    copy
  end

  def connect(*, to other : ProtocolAgent, in browser : AgentBrowser)
    browser.connect(other, self)
  end

  def compatible?(other : ProtocolAgent, in browser : AgentBrowser)
    other.compatible?(self, in: browser)
  end
end

# Birth rule agents, from their host cell's point of view, are expressed
# on birth, namely after their parent cell's replication (either via a
# call to `replicate()` or by making a copy using the GUI). Additionally,
# birth rules are expressed when they're changed using the GUI.
class BirthRuleAgent < RuleAgent
  protected getter editor = BirthRuleEditor.new(BirthRuleEditorState.new, BirthRuleEditorView.new)

  def_drain_as BirthRuleEditor, BufferEditorColumnInstant

  # Unconditionally expresses this birth agent's rule for the given
  # *receiver* cell avatar.
  def express(receiver : CellAvatar)
    rule.express(self, receiver)
  end

  def icon
    Icon::BirthRule
  end

  def icon_color
    SF::Color.new(0xFF, 0xE0, 0x82)
  end
end

# A heartbeat rule agent owns a `HeartbeatRule`. `Cell`'s heartbeat is
# a a piece of code that the cell periodically expresses . The period can
# range from a single tick (that is, no period) to every millisecond,
# every second, and so on.
class HeartbeatRuleAgent < RuleAgent
  protected getter editor = HeartbeatRuleEditor.new(HeartbeatRuleEditorState.new, HeartbeatRuleEditorView.new)

  def initialize(tank : Tank)
    super

    @start = Time.monotonic
    @pausestart = @start
  end

  def_drain_as HeartbeatRuleEditor, BufferEditorColumnInstant

  # Returns the period of this heartbeat agent. If nil is returned, this
  # agent wants to run every tick. Otherwise, the returned `Time::Span`
  # contains the desired period.
  def period? : Time::Span?
    rule.@signature.as(HeartbeatRuleSignature).period?
  end

  # Expresses this heartbeat agent's rule if time is due for the
  # given *receiver* cell avatar.
  #
  # By invoking this method, the caller gives this heartbeat agent
  # an opportunity to expresses its associated rule, but it may not
  # necessarily choose to express it.
  def express(receiver : CellAvatar)
    return unless enabled?

    if period = period?
      time = Time.monotonic
      elapsed = time - @start
      return if elapsed < period

      @start = time
    end

    rule.express(self, receiver: receiver)
  end

  def enable
    super

    @start += Time.monotonic - @pausestart
  end

  def disable
    super

    @pausestart = Time.monotonic
  end

  def icon
    Icon::HeartbeatRule
  end

  def icon_color
    SF::Color.new(0xEF, 0x9A, 0x9A)
  end
end

# Keyword rule agents react to vesicles that have hit their host cell.
class KeywordRuleAgent < RuleAgent
  protected getter editor = KeywordRuleEditor.new(KeywordRuleEditorState.new, KeywordRuleEditorView.new)

  def_drain_as KeywordRuleEditor, BufferEditorColumnInstant

  # Returns whether the given *vesicle* matches this keyword agent's rule.
  #
  # Rules determine for themselves whether they match a vesicle: some
  # may match all vesicles unconditionaly, some may match only vesicles
  # whose message has a particular keyword, etc.
  def matches?(vesicle : Vesicle) : Bool
    rule.matches?(vesicle)
  end

  # Unconditionally expresses this keyword agent's rule for the given
  # *receiver* cell avatar. Assumes *vesicle* `matches?`.
  def express(receiver : CellAvatar, vesicle : Vesicle)
    rule.express(self, receiver, vesicle)
  end

  def icon
    Icon::KeywordRule
  end

  def icon_color
    SF::Color.new(0x90, 0xCA, 0xF9)
  end
end
