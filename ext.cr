# Represents a two-dimensional vector.
struct Vector2
  getter x : Float64
  getter y : Float64

  def initialize(x, y)
    @x = x.to_f64
    @y = y.to_f64
  end

  def initialize(sf : SF::Vector2)
    initialize(sf.x, sf.y)
  end

  # Adds components of this and *other*.
  def +(other : Vector2)
    (@x + other.x).at(@y + other.y)
  end

  # Adds components of this and *other*.
  def +(other : Number)
    (@x + other).at(@y + other)
  end

  # Subtracts components of *other* from this.
  def -(other : Vector2)
    (@x - other.x).at(@y - other.y)
  end

  # Subtracts *other* from both components.
  def -(other : Number)
    (@x - other).at(@y - other)
  end

  # Multiplies both components by *other*.
  def *(other : Number)
    (@x * other).at(@y * other)
  end

  # Multiplies this vector's components by *other*'s components.
  def *(other : Vector2)
    (@x * other.x).at(@y * other.y)
  end

  # Divides both components by *other*.
  def /(other : Number)
    (@x / other).at(@y / other)
  end

  # Returns the angle of this vector from origin.
  def angle
    Math.atan2(@y, @x)
  end

  # Componentwise max() with *other*.
  def max(other : Vector2)
    Math.max(@x, other.x).at(Math.max(@y, other.y))
  end

  # Returns the components of this vector in a tuple.
  def xy
    {@x, @y}
  end

  # Returns the corresponding SFML floating-point vector.
  def sf
    SF.vector2f(@x, @y)
  end

  # Returns the corresponding SFML integer vector.
  def sfi
    SF.vector2i(@x.to_i, @y.to_i)
  end

  # Returns the corresponding Chipmunk vector.
  def cp
    CP.v(@x, @y)
  end
end

abstract struct Number
  # Returns a `Vector2` from this number to *other* number.
  def at(other : Number)
    Vector2.new(self, other)
  end

  # Assuming this number is an angle *in radians*, returns
  # the corresponding direction vector.
  def dir
    Vector2.new(Math.cos(self), Math.sin(self))
  end

  def map(from inp : Range, to outp : Range)
    outp.begin + (outp.size / inp.size) * (self - inp.begin)
  end
end

module Math
  # Returns the opposite of *angle* (both in radians).
  def opposite(angle : Number)
    (angle + PI) % TAU
  end

  # Converts *degrees* to radians.
  def radians(degrees : Number)
    theta = degrees * (PI / 180)
    theta - TAU * ((theta + PI) / TAU).floor
  end

  # Converts *radians* to degrees [0; 360].
  def degrees(radians : Number)
    angle = radians * (180 / PI)
    angle < 0 ? angle + 360 : angle
  end
end

# A very primitive `SF::Clock`-based scheduler that doesn't
# spawn fibers.
class TimeTable
  struct Entry
    getter? repeating : Bool

    def initialize(@clock : SF::Clock, @period : Time::Span, @code : ->, @repeating : Bool)
    end

    # Returns the progress of this entry: a number from 0 to 1
    # signifying how close this entry is to running.
    def progress : Float64
      progress = @clock.elapsed_time.as_milliseconds / @period.total_milliseconds
      # Timing depends on framerate, therefore may overrun. Don't
      # do anything about it & just clamp!
      progress.clamp(0.0..1.0)
    end

    # Checks if time has come and runs the code. Returns whether
    # the entry is complete. Repeating entries are never complete.
    def run?
      delta = @clock.elapsed_time.as_milliseconds - @period.total_milliseconds
      return false unless delta >= 0

      unless repeating?
        @code.call
        return true
      end

      # We might have missed some...
      count_f = (delta / @period.total_milliseconds).trunc + 1
      count_f.to_i.times { @code.call }

      @clock.restart

      false
    end
  end

  @tasks = {} of UUID => Entry

  # Executes *block* every *period* of time. Returns task identifier
  # so that you can e.g. cancel the task or change its period.
  def every(period : Time::Span, &code : ->) : UUID
    UUID.random.tap do |id|
      @tasks[id] = Entry.new(SF::Clock.new, period, code, repeating: true)
    end
  end

  # Executes *block* after a *period* of time. Returns task identifier
  # so that you can e.g. cancel the task or change its period.
  def after(period : Time::Span, &code : ->) : UUID
    UUID.random.tap do |id|
      @tasks[id] = Entry.new(SF::Clock.new, period, code, repeating: false)
    end
  end

  # Cancels the given *task*.
  def cancel(task : UUID)
    @tasks.delete(task)
  end

  # Changes the configuration of an existing *task*.
  #
  # *period* specifies the period with which the task is going
  # to run.
  #
  # *repeating* specifies whether the task is repeating (like `every`)
  # or not (like `after`).
  #
  # If either of these options is `nil`, the old value is used.
  #
  # Raises if *task* does not exist.
  def change(task : UUID, period : Time::Span? = nil, repeating : Bool? = nil)
    entry = @tasks[task]

    @tasks[task] = entry.copy_with(
      period: period || entry.period,
      repeating: repeatng.nil? ? entry.repeating : repeating,
    )

    nil
  end

  # Returns the progress (from 0 to 1) of an existing *task*.
  def progress(task : UUID) : Float64
    entry = @tasks[task]
    entry.progress
  end

  # Runs tasks that need to be run.
  def tick
    completed = [] of UUID

    @tasks.each do |task, entry|
      if complete = entry.run?
        completed << task
      end
    end

    completed.each { |task| cancel(task) }
  end
end
