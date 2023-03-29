class String
  # Same as `each_byte` but starts iterating from *offset*-th byte.
  def each_byte(*, from offset : Int)
    unsafe_byte_slice(offset, count: bytesize - offset).each do |byte|
      yield byte
    end
  end

  # Same as `each_char_with_index` but starts iterating from
  # *offset*-th character.
  def each_char_with_index(*, from offset : Int)
    if single_byte_optimizable?
      each_byte(from: offset) do |byte|
        yield (byte < 0x80 ? byte.unsafe_chr : Char::REPLACEMENT), offset
        offset += 1
      end
    else
      Char::Reader.new(self, offset).each do |char|
        yield char, offset
        offset += 1
      end
    end
  end
end

class Array
  def clear_from(start : Int)
    (@buffer + start).clear(@size - start)
    @size = start
  end
end

# `TextBuffer` is an abstraction over a string and an array
# of line bounds (see `Line`) in that string. These bounds are
# recomputed after every `update` (e.g. on every keystroke).
#
# The latter is done as quickly as possible, so there is little
# performance penalty in exchange for great ease-of-use.
class TextBuffer
  # Characters per line, on average. A heuristic used to pre-
  # allocate the line array.
  AVG_CPL = 40

  getter string : String

  def initialize(@string = "")
    @lines = Array(Line).new(size // AVG_CPL)

    update(@string)
  end

  # Returns the amount of characters in this buffer.
  delegate :size, to: @string

  # Recalculates the line array starting from the *lineno*-th line.
  private def refresh(lineno = 0)
    @memo.clear

    if @lines.empty? || (first = fetch_line?(lineno)).nil?
      start = 0
      lineno = 0
    else
      start = first.b
      lineno = first.ord
    end

    # Recalculate the line start/end indices after start.
    # This will overwrite existing lines, and leave excess
    # old lines.
    @string.each_char_with_index(from: start) do |char, index|
      next unless char == '\n'

      # Add the line. Clients can then use it to access the
      # buffer in bounds of the line.
      line = Line.new(self, lineno, start, index)

      if lineno < lines
        @lines[lineno] = line
      else
        @lines << line
      end

      start = index + 1
      lineno += 1
    end

    # Get rid of excess old lines, if there are any.
    if lineno < lines
      @lines.clear_from(lineno)
    end

    self
  end

  # Sets buffer string to *string*.
  def update(string : String, lineno = 0)
    @string = string.ends_with?('\n') ? string : string + '\n'

    refresh(lineno)
  end

  # Yields buffer string to the block. Updates buffer string
  # with block result.
  def update(lineno = 0)
    update((yield @string), lineno)
  end

  # Slices this buffer from *b*egin index to *e*nd index.
  # Both ends are included.
  def slice(b : Int, e : Int)
    if b == 0 && e == size - 1
      @string
    else
      @string[b, e - b + 1]
    end
  end

  # Returns the *index*-th character in this buffer.
  def [](index : Int)
    @string[index]
  end

  # Returns the *index*-th line, or raises.
  def fetch_line(index : Int)
    fetch_line?(index) || raise IndexError.new
  end

  # Returns the *index*-th line, or nil.
  def fetch_line?(index : Int)
    return if index.negative?

    @lines[index]?
  end

  # Returns the line at the given character *index*, or raises.
  def line_at(index : Int)
    line_at?(index) || raise IndexError.new
  end

  # Index-to-line memo. Between updates, many calls with the same
  # index go to `line_at?`, so this map tries to make that just a
  # bit faster.
  #
  # Note that this map could get 1000s of entries if you e.g. spam
  # selections without changing anything.
  @memo = {} of Int32 => Line

  # Returns the line at the given character *index*, or nil.
  def line_at?(index : Int)
    @memo.fetch(index) do
      @lines
        .bsearch { |line| index.in?(line) || index < line.b }
        .try { |line| @memo[index] = line }
    end
  end

  # Non-whitespace characters that terminate word boundary search.
  WORDSTOP = "`~!@#$%^&*()-=+[{]}|;:'\",.<>/?"

  # Finds word begin position by going back as far as possible,
  # stopping either on word stop characters `WORDSTOP` or the
  # first whitespace.
  def word_begin_at(index : Int)
    return 0 if index <= 0

    reader = Char::Reader.new(@string, index)

    while reader.has_previous?
      char = reader.previous_char
      if char.in?(WORDSTOP) || char.whitespace?
        reader.next_char
        break
      end
    end

    Math.max(reader.pos, 0)
  end

  # Find end position by going forth as far as possible, stopping
  # either on word stop characters or the first whitespace.
  def word_end_at(index : Int)
    return size - 1 if index >= size - 1

    reader = Char::Reader.new(@string, index)

    while reader.has_next?
      char = reader.next_char
      if char.in?(WORDSTOP) || char.whitespace?
        break
      end
    end

    Math.min(reader.pos, size - 1)
  end

  # Returns the amount of lines in this buffer.
  def lines
    @lines.size
  end

  # Two buffers are equal if their strings are equal.
  def_equals_and_hash @string
end
