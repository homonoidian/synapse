# Includers can manage `Halo` objects and create halo drawables.
module IHaloRecipient
  @halos = Set(Halo).new

  # Returns a drawable for a halo of the given *color*.
  abstract def halo(color : SF::Color) : SF::Drawable

  # Adds *halo* to this object's list of halos.
  #
  # You probably don't want to call this method directly. Let *halo*
  # insert itself by calling `Halo#summon`.
  def insert(halo : Halo)
    @halos << halo
  end

  # Removes *halo* from this object's list of halos.
  #
  # You probably don't want to call this method directly. Let *halo*
  # delete itself by calling `Halo#dismiss`.
  def delete(halo : Halo)
    @halos.delete(halo)
  end

  # Yields *non-overlay* halos of this object followed by their
  # corresponding drawables.
  #
  # See `Halo#overlay?`.
  def each_halo_with_drawable(&)
    @halos.each do |halo|
      next if halo.overlay?

      yield halo, halo.to_drawable
    end
  end

  # Yields *overlay* halos of this object followed by their
  # corresponding drawables.
  #
  # See `Halo#overlay?`
  def each_overlay_halo_with_drawable(&)
    @halos.each do |halo|
      next unless halo.overlay?

      yield halo, halo.to_drawable
    end
  end
end

# Halos are rings around `IHaloRecipient` objects.
class Halo
  # Returns whether this halo is an overlay halo.
  #
  # Overlay halos are drawn on top of the recipient object, and are
  # usually semi-transparent.
  getter? overlay : Bool

  # Holds whether this halo should be highlighted.
  #
  # Highlighting is automatic and is done using LCH, by increasing
  # the lightness of the original color of this halo.
  property? highlight = false

  def initialize(@recipient : IHaloRecipient, @color : SF::Color, *, @overlay = false)
  end

  # Adds this halo to the recipient.
  def summon
    @recipient.insert(self)
  end

  # Removes this halo from the recipient.
  def dismiss
    @recipient.delete(self)
  end

  # Asks the recipient to generate a drawable corresponding to
  # this halo. Returns the drawable.
  def to_drawable
    if highlight?
      _, c, h = LCH.rgb2lch(@color.r, @color.g, @color.b)
      color = SF::Color.new(*LCH.lch2rgb(70, c, h), @color.a)
    else
      color = @color
    end

    @recipient.halo(color)
  end

  # Returns whether *agent* is the recipient of this halo.
  def recipient?(agent : Agent)
    @recipient.same?(agent)
  end

  # Returns whether this halo includes the given *point*.
  def includes?(point : Vector2)
    @recipient.includes?(point)
  end

  def_equals_and_hash @recipient, @color, @overlay
end
