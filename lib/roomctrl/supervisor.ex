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
      )
      # Supervisor.child_spec(
      #   {Room.Controller,
      #    [
      #      :hass,
      #      [
      #        name: "living",
      #        #  sensor_timeout: 1_000,
      #        input: {InputDriver.Ikea5Btn, ["sensor.living_remote_action"], nil},
      #        input:
      #          {InputDriver.IkeaMotionSensor, ["binary_sensor.living_motion_dining_occupancy"],
      #           nil},
      #        input:
      #          {InputDriver.IkeaMotionSensor, ["binary_sensor.living_motion_entrance_occupancy"],
      #           nil},
      #        input:
      #          {InputDriver.IkeaMotionSensor, ["binary_sensor.living_motion_kitchen_occupancy"],
      #           nil}
      #      ]
      #    ]},
      #   id: :room_living
      # )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
