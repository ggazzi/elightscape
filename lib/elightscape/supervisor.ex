defmodule Elightscape.Supervisor do
  use Supervisor
  require Logger

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  @impl true
  def init(_config) do
    children = [
      {Hass, [name: :hass]},
      Supervisor.child_spec(
        {Room.Controller.Supervisor,
         {
           :hass,
           :mqtt,
           name: "bedroom",
           input: {InputDriver.Ikea.RemoteTradfri, entity_id: "remote_bedroom"},
           input: {InputDriver.Ikea.MotionSensorTradfri, entity_id: "motion_bedroom_shelves"}
         }},
        id: :bedroom
      ),
      Supervisor.child_spec(
        {Room.Controller.Supervisor,
         {
           :hass,
           :mqtt,
           name: "living",
           input: {InputDriver.Ikea.RemoteTradfri, entity_id: "remote_living"},
           input: {InputDriver.Ikea.MotionSensorTradfri, entity_id: "motion_entrance"},
           input: {InputDriver.Ikea.MotionSensorTradfri, entity_id: "motion_dining"},
           input: {InputDriver.Ikea.MotionSensorTradfri, entity_id: "motion_kitchen"}
         }},
        id: :living
      ),
      Supervisor.child_spec(
        {Room.Controller.Supervisor,
         {
           :hass,
           :mqtt,
           name: "bathroom",
           input: {InputDriver.Ikea.RemoteStyrbar, entity_id: "remote_bathroom"},
           input: {InputDriver.Ikea.MotionSensorTradfri, entity_id: "motion_bathroom"}
         }},
        id: :bathroom
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
