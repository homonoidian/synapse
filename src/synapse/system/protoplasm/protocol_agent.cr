# Protocol agents group `RuleAgent`s and route vesicles to them. A disabled
# protocol agent doesn't route vesicles, and keeps the subordinate rule
# agents unreachable -- globally unreachable if they can't be reached
# through another protocol.
class ProtocolAgent < Agent
  protected getter editor = ProtocolEditor.new(ProtocolEditorState.new, ProtocolEditorView.new)

  def_drain_as ProtocolEditor, ProtocolEditorInstant

  # Copies this protocol agent and all subordinate rule agents, asking
  # *browser* for all necessary information. Then, connects the copied
  # subordinate rules to the copied protocol agent.
  def copy(*, in browser : AgentBrowser)
    protocol = browser.summon(ProtocolAgent, coords: mid)
    protocol.drain(@editor)
    browser.each_rule_agent(of: self, &.copy(under: protocol, in: browser))
    protocol
  end

  def copy(protoplasm : Protoplasm)
    copy = ProtocolAgent.new(protoplasm)
    copy.mid = mid
    copy.drain(@editor)
    copy.summon
    copy
  end

  # Changes the name of this protocol to *name*.
  def rename(name : String)
    editor.rename(name)
  end

  # Returns the logical name of this protocol agent.
  #
  # `title?` is the visual name.
  def name?
    editor.title?
  end

  def icon
    Icon::Protocol
  end

  def icon_color
    SF::Color::White
  end

  def connect(*, to other : RuleAgent, in browser : AgentBrowser)
    browser.connect(self, other)
    other.connected(self)
  end

  def compatible?(other : RuleAgent, in browser : AgentBrowser)
    !browser.connected?(self, other)
  end
end
