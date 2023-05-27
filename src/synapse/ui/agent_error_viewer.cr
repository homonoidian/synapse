# A component for displaying agent errors. Drawn as an error message
# box pointing to the failed agent, with a scrollbar on top in case
# there is more than one message.
class AgentErrorViewer
  def initialize
    #
    # Tally of errors.
    #
    @errors = {} of String => Int32

    #
    # Currently displayed error.
    #
    @current = 0
  end

  # Returns whether this viewer currently holds no errors.
  def any?
    !@errors.empty?
  end

  # Returns whether this viewer is currently displaying the
  # first error.
  def at_first?
    @current == 0
  end

  # Returns whether this viewer is currently displaying the
  # last error.
  def at_last?
    @current == @errors.size - 1
  end

  # Starts showing the previous error if there is one.
  def to_prev
    return if at_first?

    @current -= 1
  end

  # Starts showing the next error if there is one.
  def to_next
    return if at_last?

    @current += 1
  end

  # Appends an error *message* into this viewer, and starts showing it.
  def append(message : String)
    if @errors.has_key?(message)
      @errors[message] += 1
      return
    end

    @errors[message] = 0
    @current = @errors.size - 1
  end

  # Removes the given error *message* from this viewer if it exists.
  def delete(message : String)
    return unless index = @errors.index(message)

    @errors.delete_at(index)
    @current -= 1 if @current >= index
  end

  # Removes all errors.
  def clear
    @errors.clear
    @current = 0
  end

  # Specifies the padding for the content of this viewer.
  def padding
    5.at(3)
  end

  # Paints this viewer on *target*, pointing to (and near) *agent*.
  def paint(*, on target : SF::RenderTarget, for agent : Agent)
    return unless any?

    error = SF::Text.new(@errors.keys[@current], FONT_BOLD, 11)

    extent = Vector2.new(error.size) + padding*2
    origin = agent.mid - extent.y + agent.class.radius.xy * 1.5.at(-1.5)

    bg = SF::RectangleShape.new
    bg.position = origin.sfi
    bg.size = extent.sfi
    bg.fill_color = SF::Color.new(0xEF, 0x9A, 0x9A, 0xdd)

    src = agent.mid - agent.class.radius.y
    dst = origin + extent.y.y
    dir = dst - src

    connector = SF::RectangleShape.new
    connector.size = SF.vector2f(dir.magn, 2)
    connector.position = src.sf
    connector.rotate(Math.degrees(Math.atan2(dir.y, dir.x)))
    connector.fill_color = SF::Color.new(0xEF, 0x9A, 0x9A)

    connector_tip = SF::CircleShape.new
    connector_tip.radius = 3
    connector_tip.position = (src - connector_tip.radius).sf
    connector_tip.fill_color = SF::Color.new(0xEF, 0x9A, 0x9A)

    target.draw(connector)
    target.draw(connector_tip)
    target.draw(bg)

    error.position = (origin + padding).sfi
    error.fill_color = SF::Color.new(0xB7, 0x1C, 0x1C)
    target.draw(error)

    return if @errors.size < 2

    scrollbar = SF::RectangleShape.new
    scrollbar.fill_color = SF::Color.new(0x51, 0x51, 0x51)
    scrollbar.size = SF.vector2f(bg.size.x + bg.outline_thickness*2, 6)
    scrollbar.position = SF.vector2f(bg.position.x - bg.outline_thickness, bg.position.y - scrollbar.size.y - 3)

    # Compute width of the scrollhead
    scrollhead_lo = 4
    scrollhead_hi = scrollbar.size.x - scrollhead_lo

    scrollhead_width = (scrollhead_hi - scrollhead_lo) / @errors.size
    scrollhead_offset = @current * scrollhead_width + scrollhead_lo

    scrollhead = SF::RectangleShape.new
    scrollhead.fill_color = SF::Color.new(0x71, 0x71, 0x71)
    scrollhead.size = SF.vector2f(scrollhead_width, 3)
    scrollhead.position = scrollbar.position + SF.vector2(scrollhead_offset, (scrollbar.size.y - scrollhead.size.y)/2)

    target.draw(scrollbar)
    target.draw(scrollhead)
  end
end
