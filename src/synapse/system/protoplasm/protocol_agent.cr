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

  # Start times and enabled flags for heartbeat agents received
  # in `heartbeat`.
  @_starttimes = {} of HeartbeatRuleAgent => {Time::Span, Bool}

  # The time when this protocol was paused (disabled).
  @_pausetime = Time.monotonic

  def enable
    super

    @_starttimes.transform_values! do |starttime, enabled|
      {starttime + (Time.monotonic - @_pausetime), enabled}
    end

    nil
  end

  def disable
    super

    @_pausetime = Time.monotonic

    nil
  end

  # Expresses due heartbeat agents from *agents_readonly* set for *receiver*.
  #
  # As the name suggests, the *agents_readonly* set is only used in a
  # readonly manner, and therefore can be reused by the caller.
  def heartbeat(agents_readonly : Set(HeartbeatRuleAgent), receiver : CellAvatar)
    return unless enabled?

    time = Time.monotonic

    agents_readonly.each do |agent|
      #
      # Add missing agents to the table.
      #
      unless entry = @_starttimes[agent]?
        @_starttimes[agent] = {time, agent.enabled?}
        next
      end

      #
      # Update enabled status of existing agents.
      #
      starttime, enabled = entry
      @_starttimes[agent] = {starttime, agent.enabled?}

      #
      # If detected a disabled -> enabled transition, offset starttime of
      # agent by the length of the pause (agent itself knows when its pause
      # had started).
      #
      if enabled != agent.enabled? && enabled == false
        @_starttimes[agent] = {starttime + (time - agent.pausestart), true}
      end
    end

    #
    # Get rid of entries for absent agents.
    #
    @_starttimes.select! do |agent, _|
      agent.in?(agents_readonly)
    end

    #
    # Express agents whose periods say they want to be expressed.
    #
    @_starttimes.each do |agent, (starttime, enabled)|
      return unless enabled

      if period = agent.period?
        elapsed = time - starttime
        next if elapsed < period
        @_starttimes[agent] = {time, enabled}
      end

      agent.express(receiver)
    end
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
