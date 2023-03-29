# Represents a logical line in a `TextBuffer`.
struct Line
  # Returns the ordinal of this line.
  getter ord : Int32

  # Returns the index where this line starts.
  getter b : Int32

  # Returns the index where this line ends.
  getter e : Int32

  def initialize(@buf : TextBuffer, @ord, @b, @e)
  end

  # Returns whether this line is the first line.
  def first_line?
    ord.zero?
  end

  # Returns whether this line is the last line.
  def last_line?
    ord == @buf.lines - 1
  end

  # Returns whether this line is in the *other* buffer.
  def in_buffer?(other : TextBuffer)
    @buf.same?(other)
  end

  # Yields each character in this line.
  def each_char
    b.upto(e) do |index|
      yield @buf[index]
    end
  end

  # Yields lines starting from this line and up to *other*
  # line, both included.
  def upto(other : Line)
    return unless other.in_buffer?(@buf)

    ord.upto(other.ord) do |mid|
      yield @buf.line(mid)
    end
  end

  # Returns a slice of this line's content.
  def slice(b : Int, e : Int)
    @buf.slice(self.b + b, self.b + e)
  end

  # Returns the content of this line.
  def content
    @buf.slice(b, e)
  end

  # Returns the *index*-th character in this line.
  def [](index : Int)
    @buf[b + index]
  end

  # Returns whether this line is empty.
  def empty?
    size.zero?
  end

  # Returns the amount of characters in this line.
  def size
    e - b
  end

  # Returns whether *index* is in this line's bounds.
  def includes?(index : Int)
    b <= index <= e
  end

  # Returns whether *range* is completely included in the bounds
  # of this line.
  def includes?(range : Range)
    includes?(range.begin) && includes?(range.end)
  end

  def inspect(io)
    io << "<Line ord=" << ord << " " << b << ":" << e << ">"
  end

  # Two lines are equal if their buffers and bounds are equal.
  def_equals_and_hash @buf, b, e
end
