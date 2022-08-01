defmodule Elightscape.Supervisor do
  use Supervisor
  require Logger

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  @impl true
  def init(config) do
    children = [
      {Hass, [name: :hass]},
      Supervisor.child_spec(
        {Room.Controller,
         [
           :hass,
           :mqtt,
           [
             name: "bedroom",
             input: {InputDriver.Ikea.RemoteTradfri, ["remote_bedroom"], nil},
             input: {InputDriver.Ikea.MotionSensorTradfri, ["motion_bedroom_shelves"], nil}
           ]
         ]},
        id: :room_bedroom
      ),
      Supervisor.child_spec(
        {Room.Controller,
         [
           :hass,
           :mqtt,
           [
             name: "living",
             input: {InputDriver.Ikea.RemoteTradfri, ["remote_living"], nil},
             input: {InputDriver.Ikea.MotionSensorTradfri, ["motion_entrance"], nil},
             input: {InputDriver.Ikea.MotionSensorTradfri, ["motion_dining"], nil},
             input: {InputDriver.Ikea.MotionSensorTradfri, ["motion_kitchen"], nil}
           ]
         ]},
        id: :room_living
      ),
      Supervisor.child_spec(
        {Room.Controller,
         [
           :hass,
           :mqtt,
           [
             name: "bathroom",
             input: {InputDriver.Ikea.RemoteStyrbar, ["remote_bathroom"], nil},
             input: {InputDriver.Ikea.MotionSensorTradfri, ["motion_bathroom"], nil}
           ]
         ]},
        id: :room_bathroom
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
