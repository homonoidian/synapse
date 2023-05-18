# Agents normally live in the `Protoplasm` (although any `Tank` will do).
# They manage incoming vesicles as well as the lifecycle of a `Cell`. They
# also own an `AgentEditor`, a GUI component useful for visualizing the
# code "guts" of agents.
abstract class Agent < CircularEntity
  include SF::Drawable

  include Inspectable
  include IDraggable
  include IHaloSupport
  include IRemixIconView

  def initialize(tank : Tank)
    super(tank, self.class.color, lifespan: nil)
  end

  def self.radius
    16
  end

  # Specifies the color in which this kind of agent should be painted.
  def self.color
    SF::Color.new(0x42, 0x42, 0x42)
  end

  # Returns the editor associated with this agent.
  protected abstract def editor

  # Summons a copy of this agent in the given *browser*.
  abstract def copy(*, in browser : AgentBrowser)

  # Summons a copy of this agent in *protoplasm*.
  abstract def copy(protoplasm : Protoplasm)

  @errors = ErrorMessageViewer.new

  # Returns whether this agent has failed, that is, whether there
  # are any errors associated with this agent.
  def failed?
    @errors.any?
  end

  # Tells the error message viewer of this agent to show the previous
  # error message, if any.
  def to_prev_error
    @errors.to_prev
  end

  # Tells the error message viewer of this agent to show the next
  # error message, if any.
  def to_next_error
    @errors.to_next
  end

  # Handles failure of this agent with the given error *message*:
  # tells the error message viewer to display an error with the
  # given *message*.
  def fail(message : String)
    @errors.insert(ErrorMessage.new(message))

    halo = Halo.new(self, SF::Color.new(0xE5, 0x73, 0x73, 0x33), overlay: false)
    halo.summon
  end

  # Clears all reported errors by this agent. Removes the error halo.
  def unfail
    @errors.clear
    @halos.each &.dismiss
  end

  # Returns whether this agent is enabled.
  #
  # A disabled rule is not expressed. A disabled protocol does not
  # let vesicles through to its rules. Unless the vesicles find their
  # way through another, enabled protocol, they won't be reacted to.
  getter? enabled = true

  # Enables this agent. This agent will start to express its rule
  # as usual.
  def enable
    @enabled = true
  end

  # Disables this agent. This means that this agent won't express its
  # rule until it is `enable`d.
  def disable
    @enabled = false
  end

  # Toggles between `enable` and `disable`.
  def toggle
    enabled? ? disable : enable
  end

  # Returns the title (visual name) of this agent, or nil.
  #
  # The title will be displayed as a hint to the right of this agent.
  # It can be used to e.g. indicate the name of the rule expressed by
  # this agent etc.
  def title? : String?
    editor.title?
  end

  # Registers this agent in the given *browser*.
  def register(*, in browser : AgentBrowser)
    browser.submit(editor)
  end

  # Unregisters this agent in the given *browser*.
  def unregister(*, in browser : AgentBrowser)
    browser.withdraw(editor)
  end

  # Builds and returns a `CP::Constraint::DampedString` between this and
  # *other* agents configured according to the arguments.
  def spring(*, to other : Agent, **kwargs)
    other.spring(@body, **kwargs)
  end

  # Builds and returns a `CP::Constraint::DampedString` between this agent's
  # body and the given *body* configured according to the arguments.
  def spring(body : CP::Body, length : Number, stiffness : Number, damping : Number)
    CP::Constraint::DampedSpring.new(@body, body, CP.v(0, 0), CP.v(0, 0), length, stiffness, damping)
  end

  # Builds and returns a `CP::Constraint::SlideJoint` between this and
  # *other* agents configured according to the arguments.
  def slide_joint(*, with other : Agent, **kwargs)
    other.slide_joint(@body, **kwargs)
  end

  # Builds and returns a `CP::Constraint::SlideJoint` between this agent's
  # body and the given *body* configured according to the arguments.
  def slide_joint(body : CP::Body, min : Number, max : Number)
    CP::Constraint::SlideJoint.new(@body, body, CP.v(0, 0), CP.v(0, 0), min, max)
  end

  # Opens the editor for this agent in the given agent *browser* unless
  # it is already open.
  def edit(*, in browser : AgentBrowser)
    return if browser.open?(editor)

    browser.open(editor, for: self)
  end

  # Packs this agent into the given *ruleset*.
  #
  # To *pack* an agent means to create a compact, self-sufficient
  # description of it. This description is oftentimes transferred
  # in a message. The receiving side could then "materialize" it
  # into an agent.
  def pack(*, into ruleset)
    ruleset[rule] = editor.capture
  end

  # Creates an edge between this and *other* agents in *browser*.
  #
  # Defined as a noop on `Agent`. Subclasses decide for themselves on
  # how (and with whom) they are going to handle connections.
  #
  # Assumes this and other are compatible. If you're unsure, you can
  # check for whether this is the case using `compatible?`.
  def connect(*, to other : Agent, in browser : AgentBrowser)
  end

  # Returns whether this and *other* agents are compatible (and therefore
  # connectible, see `connect`) with each other in the given *browser*.
  def compatible?(other : Agent, in browser : AgentBrowser)
    false
  end

  # Fills the editor of this agent with the captured content of the
  # *other* editor.
  def drain(other : AgentEditor)
  end

  # :nodoc:
  macro def_drain_as(type, instant_type)
    # Fills the editor of this agent with the captured content of *other*.
    def drain(other : {{type}})
      editor.drain(other)
    end

    # Fills the editor of this agent with the content of the given *instant*.
    def drain(instant : {{instant_type}})
      editor.drain(instant)
    end
  end

  # Specifies the outline color of this agent's circular body.
  def outline_color
    @tank.inspecting?(self) ? SF::Color.new(0x58, 0x65, 0x96) : SF::Color.new(0x4f, 0x63, 0x59)
  end

  def icon_font_size
    14
  end

  def halo(color : SF::Color) : SF::Drawable
    circle = SF::CircleShape.new(radius: self.class.radius * 1.3)
    circle.position = (mid - self.class.radius.xy*1.3).sf
    circle.fill_color = color
    circle
  end

  @dragged : Vector2?

  def lifted
    @dragged = mid
  end

  def dragged(delta : Vector2)
    return unless dragged = @dragged

    unless dragged == mid
      # Do a "correction burn": physics changed the agent's position
      # between dragged()s or lifted() -> dragged(). Force the agent
      # under the cursor and only then apply drag delta.
      delta += dragged - mid
    end

    self.mid += delta

    @dragged = mid
  end

  def dropped
    @dragged = nil
  end

  # Draws shadow and non-overlay halos for this agent.
  def draw_back(target : SF::RenderTarget, states : SF::RenderStates)
    if @dragged
      #
      # Draw shadow if this agent is being dragged.
      #
      shadow = SF::CircleShape.new
      shadow.radius = self.class.radius * 1.1
      shadow.position = (mid - shadow.radius + 0.at(10)).sf
      shadow.fill_color = SF::Color.new(0, 0, 0, 0x33)
      shadow.draw(target, states)
    end

    #
    # Draw non-overlay halos.
    #
    each_halo_with_drawable do |_, drawable|
      target.draw(drawable)
    end
  end

  # Draws the circular body of this agent.
  def draw_body(target : SF::RenderTarget, states : SF::RenderStates)
    circle = SF::CircleShape.new
    circle.radius = self.class.radius
    circle.position = origin.sfi
    circle.fill_color = @color
    circle.outline_thickness = @tank.inspecting?(self) ? 3 : 1
    circle.outline_color = outline_color
    circle.draw(target, states)
  end

  # Draws the "face" of this agent: draws everything on top of the
  # circular body, and the title hint.
  def draw_face(target : SF::RenderTarget, states : SF::RenderStates)
    #
    # Draw the icon in the center.
    #
    icon = icon_text
    unless enabled?
      # Force-substitute the icon to paused if this agent is paused.
      icon.string = Icon::Paused
      icon.character_size = 18
    end

    icon.position = (origin + (self.class.radius.xy - Vector2.new(icon.size)/2) - 1.y).sfi
    icon.draw(target, states)

    #
    # Draw title hint if this agent has one.
    #
    if title = title?
      name_hint = SF::Text.new(title, FONT_UI, 11)

      name_bg = SF::RectangleShape.new
      name_bg.size = (name_hint.size + (5.at(5)*2).sfi)
      name_bg.position = (mid + self.class.radius.x*2 - name_bg.size.y/2).sf
      name_bg.fill_color = SF::Color.new(0x0, 0x0, 0x0, 0x44)
      name_bg.draw(target, states)

      name_hint.color = SF::Color.new(0xcc, 0xcc, 0xcc)
      name_hint.position = (name_bg.position + 5.at(5).sf).to_i
      name_hint.draw(target, states)
    end
  end

  # Draws all that is above both the circular body and the "face" of
  # this agent. Namely: overlay halos, dark overlay that signals this
  # agent is paused, and the error message viewer that shows the errors
  # for this agent (if there are any).
  def draw_overlay(target : SF::RenderTarget, states : SF::RenderStates)
    #
    # Draw overlay halos.
    #
    each_overlay_halo_with_drawable do |_, drawable|
      target.draw(drawable)
    end

    #
    # Draw paused overlay if this agent is paused. This overlay "darkens"
    # everything else so that the user intuitively understands the agent
    # isn't doing any work.
    #
    unless enabled?
      dark_overlay = SF::CircleShape.new
      dark_overlay.radius = self.class.radius
      dark_overlay.position = origin.sfi
      dark_overlay.fill_color = SF::Color.new(0, 0, 0, 0xaa)
      target.draw(dark_overlay)
    end

    #
    # Draw error viewer that shows errors and a scrollbar (if there are
    # any errors of course).
    #
    @errors.paint(on: target, for: self)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    draw_back(target, states)
    draw_body(target, states)
    draw_face(target, states)
    draw_overlay(target, states)
  end
end
