# Exactly the same as `BufferEditorState`, but rejects input that
# contains newlines -- effectively making the buffer single-line.
class InputFieldState < BufferEditorState
  def insertable?(printable : String)
    printable.each_byte do |byte|
      if byte === '\n' || byte === '\r'
        return false
      end
    end

    true
  end
end

# An `SF::Drawable` view of `InputFieldState`.
class InputFieldView < BufferEditorView
  # Holds the maximum width of this input field, in pixels.
  #
  # If the content exceeds the maximum width, horizontal
  # scrolling will occur. If nil, input field resizes to
  # fit the content.
  property max_width : Int32?

  # Holds the minimum width of this input field, in pixels.
  property min_width = 6

  # Holds the position of this input field view.
  property position = SF.vector2f(0, 0)

  # Returns the default input field width, in pixels.
  def self.width
    100
  end

  def line_spacing
    1
  end

  def beam_color
    active? ? SF::Color.new(0x90, 0xCA, 0xF9) : super
  end

  def text_color
    active? ? SF::Color.new(0xE0, 0xE0, 0xE0) : SF::Color.new(0x9E, 0x9E, 0x9E)
  end

  # Returns the size of this field.
  def size
    SF.vector2i(@max_width || Math.max(@text.width, @min_width), @text.height)
  end

  def draw(target, states)
    if width = @max_width
      #
      # Create ribbon if it does not exist or if its size is
      # not equal to the freshly computed field size.
      #
      # Ribbon is the texture that contains the text and the
      # beam, and is scrolled when the beam is out of view.
      #
      unless (ribbon = @ribbon) && ribbon.size == size
        @ribbon = ribbon = SF::RenderTexture.new(size.x, size.y)
      end

      #
      # Calculate where the window into the text should begin.
      # Position the view of the ribbon appropriately.
      #
      window_start = (@beam.position.x + @beam.size.x) - size.x

      ribbon.view = SF::View.new(SF.float_rect(Math.max(window_start, 0), 0, size.x, size.y))

      #
      # Draw text and beam on ribbon.
      #
      ribbon.clear(SF::Color::Transparent)

      super(ribbon, SF::RenderStates.new)

      ribbon.display

      #
      # Draw the ribbon.
      #
      sprite = SF::Sprite.new(ribbon.texture)
      sprite.position = position
      sprite.draw(target, states)
    else
      delta = position - @text.position

      @text.position += delta
      @beam.position += delta

      super
    end

    #
    # Draw background rectangle.
    #
    bgrect = SF::RectangleShape.new
    bgrect.fill_color = beam_color
    bgrect.position = position + SF.vector2f(0, size.y - font_size//2)
    bgrect.size = SF.vector2f(size.x, 1)
    bgrect.draw(target, states)
  end
end

class InputField < BufferEditor
  @focused = false

  def initialize(state : InputFieldState, view : InputFieldView)
    super
    view.active = false
  end

  def focus
    @view.active = true
    @focused = true
    super
  end

  def blur
    @view.active = false
    @focused = false
    super
  end

  def handle(event)
    return unless @focused

    super
  end
end
