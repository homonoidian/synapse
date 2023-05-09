# A time-ordered snapshot of `ProtocolEditorState`.
#
# Allows clients to implement an undo/redo system independent
# of `ProtocolEditorState`.
#
# Also allows clients to peek into `ProtocolEditorState` at
# discrete time steps for change-awareness.
class ProtocolEditorInstant < BufferEditorRowInstant
  # Returns the unique identifier of the protocol at the time
  # when this instant was captured.
  getter id : UUID

  # Returns whether this protocol is enabled.
  getter? enabled : Bool

  def initialize(timestamp, states, selected, @id, @enabled)
    super(timestamp, states, selected)
  end

  # Initializes this instant from the parent buffer editor
  # row *instant*.
  def initialize(instant : BufferEditorRowInstant, id : UUID, enabled : Bool)
    initialize(instant.timestamp, instant.states, instant.selected, id, enabled)
  end
end

# State for a protocol editor.
#
# Protocol editors allow to create *protocol*s, which are,
# simply speaking, "umbrellas" for rules.
class ProtocolEditorState < InputFieldRowState
  def initialize
    super

    @id = UUID.random
    @enabled = true
  end

  def initialize(@id : UUID, @enabled : Bool)
    super()
  end

  def capture
    ProtocolEditorInstant.new(super, @id, @enabled)
  end

  def min_size
    1
  end

  def max_size
    1
  end

  def protocol_from(collection : ProtocolCollection)
    name = @states[0].as(ProtocolNameEditorState).string

    unless protocol = collection[@id]?
      protocol = Protocol.new(@id, name, @enabled)
      collection.summon(protocol)
    end

    protocol
  end

  def new_substate_for(index : Int)
    ProtocolNameEditorState.new
  end
end

# View for a protocol editor.
#
# Displays the protocol name, and unique identifier of the
# protocol in the caption.
class ProtocolEditorView < InputFieldRowView
  include IRemixIconView

  @id : UUID?

  # Determines whether to show slightly outset, semi-transparent
  # halo around this protocol editor.
  property? halo = false

  def new_subview_for(index : Int)
    view = ProtocolNameEditorView.new
    view.max_width = max_width
    view
  end

  def update(instant : ProtocolEditorInstant)
    super
    @id = instant.id
    @enabled = instant.enabled?
  end

  def max_width
    200
  end

  def caption_space_y
    16
  end

  def padding
    SF.vector2f(10, 10)
  end

  def origin
    super + padding
  end

  def size
    SF.vector2f(max_width, super.y) + padding*2 + SF.vector2f(0, caption_space_y)
  end

  # Specifies the background color of this editor as a whole.
  def background_color
    SF::Color.new(0x31, 0x31, 0x31)
  end

  # Specifies the color of the outline of this editor.
  def outline_color
    active? ? SF::Color.new(0x43, 0x51, 0x80) : SF::Color.new(0x3f, 0x3f, 0x3f)
  end

  # Specifies the color of the halo.
  def halo_color
    SF::Color.new(0x80, 0xaf, 0xf2)
  end

  def icon
    Icon::Protocol
  end

  def icon_color
    caption_color
  end

  # Returns the caption displayed above the rule.
  def caption
    "protocol #{@id || "<no id | bug>"}"
  end

  # Specifies the maximum amount of characters in the rule
  # caption. The rest of the caption will be truncated with
  # ellipsis `…`.
  def caption_max_chars
    32
  end

  # Specifies the color of the caption.
  def caption_color
    active? ? SF::Color.new(0xE0, 0xE0, 0xE0) : SF::Color.new(0xBD, 0xBD, 0xBD)
  end

  def draw(target, states)
    #
    # Draw background rectangle.
    #
    bgrect = SF::RectangleShape.new
    bgrect.fill_color = background_color
    bgrect.position = position
    bgrect.size = size
    bgrect.outline_thickness = 2
    bgrect.outline_color = halo? ? halo_color : outline_color
    bgrect.draw(target, states)

    #
    # Draw bottom dock rectangle.
    #
    dock = SF::RectangleShape.new
    dock.fill_color = outline_color
    dock.position = position + SF.vector2f(0, size.y - caption_space_y)
    dock.size = SF.vector2f(size.x, caption_space_y)
    dock.draw(target, states)

    #
    # Draw caption and icon.
    #
    icon = icon_text
    icon.position = dock.position + SF.vector2f(bgrect.outline_thickness, 0)
    icon.draw(target, states)

    cap = SF::Text.new(caption.trunc(caption_max_chars), FONT, 11)
    cap.position = (icon.position + SF.vector2f(icon_span_x, 0)).to_i
    cap.fill_color = caption_color
    cap.draw(target, states)

    super

    return if @enabled

    #
    # Draw dark semi-transparent overlay if protocol is disabled.
    #
    overlay = SF::RectangleShape.new
    overlay.position = position
    overlay.size = size
    overlay.fill_color = SF::Color.new(0, 0, 0, 0x66)
    overlay.draw(target, states)
  end
end

module ProtocolEditorHandler
  include Draggable(ProtocolEditorState)
end

# Protocol editor allows to create and edit protocols, which
# are, simply speaking, "umbrellas" for rules.
class ProtocolEditor
  include MonoBufferController(ProtocolEditorState, ProtocolEditorView)
  include BufferEditorHandler
  include BufferEditorRowHandler
  include ProtocolEditorHandler
  include CellEditorEntity

  delegate :halo?, :halo=, to: @view

  def append(rule : Rule, to collection : ProtocolCollection)
    protocol = @state.protocol_from(collection)
    protocol.append(rule)
  end
end
