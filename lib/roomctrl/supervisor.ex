defmodule RoomCtrl.Supervisor do
  use Supervisor
  require Logger

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  @impl true
  def init(config) do
    children = [
      {Hass.Connection, [config[:hass], name: :hass]},
      {Mqtt, [config[:mqtt], name: :mqtt]},
      Supervisor.child_spec(
        {Room.Controller,
         [
           :hass,
           :mqtt,
           [
             name: "bedroom",
             input: {InputDriver.Ikea5Btn, ["remote_bedroom"], nil},
             input: {InputDriver.IkeaMotionSensor, ["motion_bedroom_shelves"], nil}
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
             input: {InputDriver.Ikea5Btn, ["remote_living"], nil},
             input: {InputDriver.IkeaMotionSensor, ["motion_entrance"], nil},
             input: {InputDriver.IkeaMotionSensor, ["motion_dining"], nil},
             input: {InputDriver.IkeaMotionSensor, ["motion_kitchen"], nil}
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
             input: {InputDriver.Ikea5Btn, ["remote_bathroom"], nil},
             input: {InputDriver.IkeaMotionSensor, ["motion_bathroom"], nil}
           ]
         ]},
        id: :room_bathroom
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
