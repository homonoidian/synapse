# Inside Synapse `Cell`s lies their *signal environment*, which the
# system more commonly dubs the *protoplasm*.
#
# Protoplasms belong to `Cell` objects. They are a little world
# with controlled physics and distribution rules. Cells are free
# to change the physics and the rules, perhaps based on messages
# from the environment.
class Protoplasm < Tank
  include INotificationProvider

  def initialize
    super

    @space.gravity = CP.v(0, 0)
    @space.damping = 0.4
  end

  def notify(keyword : Symbol)
    @notification_handlers.each &.notify(keyword)
  end

  # Yields all agents from this protoplasm.
  def each_agent(& : Agent ->)
    @entities.each(Agent) do |agent|
      yield agent
    end
  end

  @decay_handlers = [] of IVesicleDecayHandler

  # Regsters a vesicle decay *handler* object.
  #
  # Vesicle decay handlers trigger when vesicles decay in this
  # protoplasm. They are triggered *after* the vesicle is dismissed
  # and removed from this protoplasm.
  def add_vesicle_decay_handler(handler : IVesicleDecayHandler)
    @decay_handlers << handler
  end

  @notification_handlers = [] of INotificationHandler

  # Registers a notification *handler* object.
  #
  # Notification handlers run when any entity in this protoplasm
  # sends a notification. Notifications are a simple, internal way
  # for entities to communicate within the tank that holds them,
  # provided it is an `INotificationProvider`.
  def add_notification_handler(handler : INotificationHandler)
    @notification_handlers << handler
  end

  def remove(entity : Vesicle)
    super

    # Run the decay handlers *after* the vesicle has been dismissed
    # (the caller is presumably Vesicle#dismiss) and removed from the
    # protoplasm (that's what 'super' does).
    @decay_handlers.each &.decayed(self, entity)
  end
end
