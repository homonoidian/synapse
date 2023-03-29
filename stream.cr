# A suckless reactive stream toolkit.
module Stream(T)
  # Creates and returns a stream.
  def self.new
    BaseStream(T).new
  end

  # A set of streams listening (subscribed) to this stream.
  @listeners = Set(Stream(T)).new

  # Subscribes *stream* to this stream.
  def notifies(stream)
    @listeners << stream

    stream
  end

  # Unsubscribes *stream* from events in this stream.
  def forget(stream)
    @listeners.delete(stream)

    stream
  end

  # Emits *object* to all streams that are subscribed to this stream.
  def emit(object : T)
    @listeners.each &.emit(object)
  end

  # Calls *func* before emitting an object unchanged.
  def each(func : T ->)
    notifies EachStream(T).new(func)
  end

  # :ditto:
  def each(&func : T ->)
    each(func)
  end

  # Unordrered concatenation: emits objects from both streams.
  def join(other : Stream(T))
    Stream(T).new.tap do |slave|
      notifies slave
      other.notifies slave
    end
  end

  # Emits objects from this stream in batches of *count* elements.
  def batch(count : Int32)
    slave = Stream(Array(T)).new
    batch = [] of T
    each do |object|
      batch << object
      if batch.size == count
        slave.emit(batch)
        batch = [] of T
      end
    end
    slave
  end

  # Emits an object transformed by *func*.
  def map(&func : T -> U) forall U
    Stream(U).new.tap do |slave|
      each { |object| slave.emit func.call(object) }
    end
  end

  # Emits only those objects for which *func* returns true.
  def select(&func : T -> Bool)
    Stream(T).new.tap do |slave|
      each { |object| slave.emit(object) if func.call(object) }
    end
  end

  # Emits only those objects that are of the given *type*.
  def select(type : U.class) forall U
    Stream(U).new.tap do |slave|
      each { |object| slave.emit(object) if object.is_a?(U) }
    end
  end

  # Emits only those objects that match against *pattern*
  # (using `===`).
  def select(pattern)
    self.select { |object| pattern === object }
  end

  # Emits only those objects for which *func* returns false.
  def reject(&func : T -> Bool)
    self.select { |object| !func.call(object) }
  end

  # Emits only those objects that **do not** match against
  # *pattern* (using `===`).
  def reject(pattern)
    self.select { |object| !(pattern === object) }
  end

  # Emits only if the result of *func* is not equal (`==`)
  # to the last emitted value.
  #
  # The first object is always emitted.
  def uniq(&func : T -> U) forall U
    memo = nil
    reject do |object|
      prev = memo
      memo = func.call(object)
      prev == memo
    end
  end

  # Emits only if the emitted object is not equal to the
  # previous emitted object.
  def uniq
    uniq { |object| object }
  end

  def zip(other : Stream(U)) : Stream({T, U}) forall U
    slave = Stream({T, U}).new

    a = [] of T
    b = [] of U

    each do |object|
      a.unshift(object)
      slave.emit({a.shift, b.shift}) unless b.empty?
    end

    other.each do |object|
      b.unshift(object)
      slave.emit({a.shift, b.shift}) unless a.empty?
    end

    slave
  end

  # Starts to emit when *a* emits, and stops to emit when *b*
  # emits. *now* can be passed to skip waiting for *a* to emit
  # the first time.
  def all(from a : Stream(M), until b : Stream(K), now = false) forall M, K
    slave = Stream(T).new

    notifies slave if now

    a_each = uninitialized Stream(M)
    a_each = a.each do
      notifies slave
      # Unsubscribe until we receive an object from B.
      a.forget a_each
    end

    b.each do
      forget slave
      # Subscribe now and close the "loop".
      a.notifies a_each
    end

    slave
  end
end

# :nodoc:
struct BaseStream(T)
  include Stream(T)
end

# :nodoc:
struct EachStream(T)
  include Stream(T)

  def initialize(@func : T ->)
  end

  def emit(object : T)
    @func.call(object)
    super
  end
end
