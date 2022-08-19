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
           input: {InputDriver.Ikea.MotionSensorTradfri, entity_id: "motion_bedroom_shelves"},
           light: "light_bedroom_ceiling",
           light: "light_bedroom_desk",
           light: "light_bedroom_shelves"
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
           input: {InputDriver.Ikea.MotionSensorTradfri, entity_id: "motion_kitchen"},
           light: "light_kitchen_ceiling",
           light: "light_kitchen_spot",
           light: "light_living_floor",
           light: "light_living_spot",
           light: "light_living_fairy",
           light: "light_chandelier_1",
           light: "light_chandelier_2",
           light: "light_chandelier_3",
           light: "light_chandelier_4",
           light: "light_chandelier_5"
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
           input: {InputDriver.Ikea.MotionSensorTradfri, entity_id: "motion_bathroom"},
           light: "light_bedroom_ceiling"
         }},
        id: :bathroom
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
