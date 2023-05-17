# Synapse cells (`CellAvatar`s to be precise) express rules in response
# to various signals coming from the environment or from within themselves.
#
# Rules are named bits of Lua. In order to give those bits *indirect*
# control over various properties of the receiver cell, `ExpressionContext`
# defines a number of functions and variables that map one way or
# another to what the receiver cell will do, or have had observed using
# one of its devices.
class ExpressionContext
  def initialize(@receiver : CellAvatar)
    @strength = 120.0
    @random = Random::PCG32.new(Time.local.to_unix.to_u64!)
  end

  # Computes *heading angle* (in degrees) from a list of angles
  # (in degrees) with an optional list of weights ([0; 1], sum
  # must be 1). Essentially circular mean and weighted circular
  # mean under one function.
  #
  # Synopsis:
  #
  # * `heading(...angles : number)`
  # * `heading(angles : numbers)`
  # * `heading(angles : numbers, weights : numbers)`
  def heading(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    unless stack.size > 0
      raise Lua::RuntimeError.new("heading(_): expected angles array and an optional weights array, or a list of angles")
    end

    # Use the angle list variant if the first argument is a number:
    # compute the circular mean of the angles on the stack.
    if stack.top.is_a?(Float64)
      sines = 0
      cosines = 0

      until stack.size == 0
        unless angle = stack.pop.as?(Float64)
          raise Lua::RuntimeError.new("heading(...angles): expected angle (in degrees), a number")
        end

        angle = Math.radians(angle)

        sines += Math.sin(angle)
        cosines += Math.cos(angle)
      end

      stack << Math.degrees(Math.atan2(sines, cosines))

      return 1
    end

    # Assume weights table is on top of the stack. Create and
    # populate the fweights (float weights) array. Ensure sum
    # is about 1.0 (± epsilon, for fp errors)
    if stack.size == 2
      weights = stack.pop

      unless weights.is_a?(Lua::Table)
        raise Lua::RuntimeError.new("heading(angles, weights?): weights must be an array of weights [0; 1]")
      end

      sum = 0

      fweights = weights.map do |_, weight|
        unless (weight = weight.as?(Float64)) && weight.in?(0.0..1.0)
          raise Lua::RuntimeError.new("heading(angles, weights?): weight must be a number [0; 1]")
        end

        sum += weight

        weight
      end

      eps = 0.0001
      unless (1.0 - sum).abs <= eps
        raise Lua::RuntimeError.new("heading(angles, weights?): weights sum must be equal to 1 (currently: #{sum})")
      end
    end

    # Assume angles table is on top of the stack. Convert each
    # angle to radians, and zip with weights on the fly.
    angles = stack.pop

    unless angles.is_a?(Lua::Table) && angles.size > 0
      raise Lua::RuntimeError.new("heading(angles, weights?): angles must be an array of at least one angle (in degrees)")
    end

    unless fweights.nil? || fweights.size == angles.size
      raise Lua::RuntimeError.new("heading(angles, weights?): angles array and weights array must be of the same length")
    end

    # The least expensive way to get rid of the nil.
    fweights ||= Tuple.new

    sines = 0
    cosines = 0

    angles.zip?(fweights) do |(_, angle), weight|
      unless angle = angle.as?(Float64)
        raise Lua::RuntimeError.new("heading(angles, weights?): angle (degrees) must be a number")
      end

      angle = Math.radians(angle)

      sines += (weight || 1) * Math.sin(angle)
      cosines += (weight || 1) * Math.cos(angle)
    end

    stack << Math.degrees(Math.atan2(sines, cosines))

    1
  end

  # Retrieves or assigns the strength of messages emitted by `send`
  # *in this expression context*. Meaning strength is local to the
  # specific response.
  #
  # Synopsis:
  #
  # * `strength() : number`
  # * `strength(newStrength : number) : number`
  def strength(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    if stack.size == 1
      unless strength = stack.pop.as?(Float64)
        raise Lua::RuntimeError.new("strength(newStrength): newStrength must be a number")
      end
      @strength = strength
    end

    stack << @strength

    1
  end

  # Assigns the jitter [0;1] of this cell and/or returns it.
  #
  # The following is not how jitter and entropy in general
  # are implemented but rather how it should be imagined.
  #
  # Cells "float" in an environment called *tank*. Tank features
  # a landscape of higher and lower elevation (*entropy*).
  # *jitter* determines how eagerly (and whether at all)
  # a cell must descend or ascend this landscape.
  #
  # Note that at high velocities even a high jitter won't
  # matter much. However, when entities slow down, jitter starts
  # to play a role in their motion.
  #
  # Vesicles with lower strength climb the landscape down. Their
  # jitter is calculated using a formula as they decay,
  # and cannot be set or known ahead of time.
  #
  # Synopsis:
  #
  # * `jitter() : number`
  # * `jitter(newJitter : number) : number`
  def jitter(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    if stack.size == 1
      unless (jitter = stack.pop.as?(Float64)) && jitter.in?(0.0..1.0)
        raise Lua::RuntimeError.new("jitter(newJitter): newJitter must be a number in [0; 1]")
      end

      @receiver.jitter = jitter
    end

    stack << @receiver.jitter

    1
  end

  # Samples entropy using the *entropy device*.
  #
  # The *entropy device* is one of the several abstract devices
  # cells use to "probe" the environment. Some other devices
  # include the *attack device*, *decay device*, and the
  # *evasion* device.
  #
  # Note that because the same cell may be present in multiple
  # tanks simultaneously, the sample from the *entropy device*
  # is a mean of samples from all tanks.
  #
  # Synopsis:
  #
  # * `entropy() : number`
  def entropy(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)
    stack << @receiver.entropy

    1
  end

  # Assigns or returns the ascent factor [0; 1] of this cell.
  #
  # Ascent factor determines whether this cell should *descend*
  # (ascent factor is `0.0`) or descend (ascent factor is `1.0`)
  # in the tank landscape during jitter. Values in-between are
  # obtained via weighted circular mean.
  #
  # Synopsis:
  #
  # * `ascent() : number`
  # * `ascent(newAscent : number) : number`
  def ascent(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    if stack.size == 1
      unless (ascent = stack.pop.as?(Float64)) && ascent.in?(0.0..1.0)
        raise Lua::RuntimeError.new("ascent(newAscent): newAscent must be a number in [0; 1]")
      end

      @receiver.jascent = ascent
    end

    stack << @receiver.jascent

    1
  end

  # Generates a random number using a unique, freshly seeded
  # random number generator.
  #
  # Synopsis:
  #
  # * `rand() : number`
  def rand(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)
    stack << @random.rand

    1
  end

  # Terminates message handling and makes the receiver cell
  # commit suicide. No return.
  #
  # Synopsis:
  #
  # * `die()`
  def die(state : LibLua::State)
    # Longjump (sort of) to CellAvatar#receive, systole(), dyastole(),
    # and friends.
    raise CommitSuicide.new

    1
  end

  # Summons a complete copy of this cell.
  #
  # Synopsis:
  #
  # * `replicate()`: copy all protocols, carry over whether each is
  # enabled/disabled.
  #
  # * `replicate(...protocols : owned protocol)`: copy specified protocols,
  # carry over whether each is enabled/disabled.
  #
  # * `replicate(enabled: {...owned protocol}, disabled: {...owned protocol}):
  # copy specified protocols, set enabled/disabled based on collection.
  def replicate(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    #
    # Copy all protocols, carry over whether each is enabled/disabled.
    #
    if stack.size == 0
      @receiver.replicate
      return 1
    end

    #
    # Copy specified protocols, set enabled/disabled based on collection.
    #
    if stack.size == 2 && (enabled = stack[1].as?(Lua::Table)) && (disabled = stack[2].as?(Lua::Table))
      enabled_set = Set(ProtocolAgent).new
      disabled_set = Set(ProtocolAgent).new

      enabled.each do |_, element|
        element = element.to_crystal if element.is_a?(Lua::Callable)

        unless element.is_a?(OwnedProtocol)
          raise Lua::RuntimeError.new("replicate({enabled}, disabled): expected an owned protocol, got: #{element}")
        end

        enabled_set << element._protocol
      end

      disabled.each do |_, element|
        element = element.to_crystal if element.is_a?(Lua::Callable)

        unless element.is_a?(OwnedProtocol)
          raise Lua::RuntimeError.new("replicate(enabled, {disabled}): expected an owned protocol, got: #{element}")
        end

        disabled_set << element._protocol
      end

      @receiver.replicate_with_select_protocols do |protocol|
        if keep = enabled_set.includes?(protocol)
          protocol.unpause
        elsif keep = disabled_set.includes?(protocol)
          protocol.pause
        end

        keep
      end

      return 1
    end

    #
    # Copy specified protocols, carry over whether each is enabled/disabled.
    #
    protocols = Set(ProtocolAgent).new

    until stack.size == 0
      arg = stack.pop
      arg = arg.to_crystal if arg.is_a?(Lua::Callable)

      unless arg.is_a?(OwnedProtocol)
        raise Lua::RuntimeError.new("replicate(...protocols : owned protocols): expected an owned protocol")
      end

      protocols << arg._protocol
    end

    @receiver.replicate_with_select_protocols &.in?(protocols)

    1
  end

  # Emits a message at the receiver. Strength can be assigned/
  # retrieved using `setStrength/getStength`.
  #
  # Protocols, when sent, are cloned (recursively copied).
  #
  # Synopsis:
  #
  # * `send(keyword : string)`
  # * `send(keyword : string, ...args : owned protocol|boolean|number|table|string|nil)`
  def send(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    if stack.size.zero?
      raise Lua::RuntimeError.new("send(keyword, ...args): keyword is required")
    end

    args = Array(Memorable).new(stack.size - 1)

    until stack.size == 1
      arg = stack.pop

      if arg.is_a?(Lua::Callable)
        arg = arg.to_crystal
      end

      unless arg.is_a?(MemorableValue) || arg.is_a?(OwnedProtocol)
        raise Lua::RuntimeError.new("send(keyword, ...args): argument must be an owned protocol, boolean, number, table, string, or nil")
      end

      if arg.is_a?(OwnedProtocol)
        arg = @receiver.pack(arg._protocol)
      end

      args.unshift(arg)
    end

    unless keyword = stack.pop.as?(String)
      raise Lua::RuntimeError.new("send(keyword): keyword must be a string")
    end

    @receiver.emit(keyword, args, @strength, color: CellAvatar.color(l: 80, c: 70))

    1
  end

  # Assigns compass heading and speed to the receiver. Motion does
  # not continue forever; the receiver slowly stops due to its own
  # friction and due to the environment's damping. This slightly
  # resembles swimming, hence the name.
  #
  # Synopsis:
  #
  # * `swim(heading degrees : number, speed : number)`
  def swim(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    unless (speed = stack.pop.as?(Float64)) && (heading = stack.pop.as?(Float64))
      raise Lua::RuntimeError.new("expected two numbers in swim(heading degrees, speed)")
    end

    @receiver.swim(heading, speed)

    1
  end

  # Prints to editor console.
  def print(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)
    string = (1..stack.size).join('\t') do |index|
      arg = stack[index]
      arg.nil? ? "nil" : arg
    end

    @receiver.print(string)

    1
  end

  # Begins adhering to a protocol sent by another cell.
  #
  # Synopsis:
  #
  # * `adhere(protocol : packed protocol)`
  def adhere(state : LibLua::State)
    stack = Lua::Stack.new(state, :all)

    if protocol = stack.pop.as?(Lua::Callable)
      protocol = protocol.to_crystal
    end

    unless protocol.is_a?(PackedProtocol)
      raise Lua::RuntimeError.new("adhere(protocol): expected protocol to be a packed protocol")
    end

    protocol._adhere(@receiver)

    1
  end

  # Specifies whether the cell is allowed to replicate during
  # this expression.
  def allowed_to_replicate?
    true
  end

  # Specifies whether the cell is allowed to die during
  # this expression.
  def allowed_to_die?
    true
  end

  # Populates *stack* with globals related to this expression context.
  def fill(stack : Lua::Stack)
    stack.set_global("self", @receiver.memory)
    stack.set_global("heading", ->heading(LibLua::State))
    stack.set_global("strength", ->strength(LibLua::State))
    stack.set_global("jitter", ->jitter(LibLua::State))
    stack.set_global("entropy", ->entropy(LibLua::State))
    stack.set_global("ascent", ->ascent(LibLua::State))
    stack.set_global("rand", ->rand(LibLua::State))
    stack.set_global("send", ->send(LibLua::State))
    stack.set_global("swim", ->swim(LibLua::State))
    stack.set_global("print", ->print(LibLua::State))
    stack.set_global("adhere", ->adhere(LibLua::State))

    # Expose owned protocols to the expressed rule so
    # it can e.g. toggle them on/off or share them.
    @receiver.each_owned_protocol_with_name do |protocol, name|
      stack.set_global(name, protocol)
    end

    if allowed_to_die?
      stack.set_global("die", ->die(LibLua::State))
    end

    if allowed_to_replicate?
      stack.set_global("replicate", ->replicate(LibLua::State))
    end
  end
end

# Same as `ExpressionContext`, except death and replication
# are forbidden (because e.g. replicating during birth will
# cause infinite, extremely explosive replication).
class BirthExpressionContext < ExpressionContext
  def allowed_to_die?
    false
  end

  def allowed_to_replicate?
    false
  end
end

# Subclass of `ExpressionContext` specifically for when the receiver
# cell is expressing due to a vesicle from the environment rather
# than e.g. at heartbeat or at birth.
#
# Exposes some information about the message and vesicle itself.
class VesicleExpressionContext < ExpressionContext
  def initialize(receiver : CellAvatar, @vesicle : Vesicle, @attack = 0.0)
    super(receiver)

    @message = @vesicle.message
  end

  def fill(stack : Lua::Stack)
    super

    stack.set_global("keyword", @message.keyword)
    stack.set_global("impact", @vesicle.strength)
    stack.set_global("decay", @vesicle.decay)

    stack.set_global("attack", Math.degrees(@attack))
    stack.set_global("evasion", Math.degrees(Math.opposite(@attack)))
  end
end
