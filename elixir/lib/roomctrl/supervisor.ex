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
      Supervisor.child_spec(
        {Room.Controller,
         [
           :hass,
           [
             name: "bedroom",
             # trigger: {%{:platform => :state, entity_id: "sensor.bedroom_remote_action", to: nil}, :toggle},
             input: {InputDriver.Ikea5Btn, ["sensor.bedroom_remote_action"], nil}
           ]
         ]},
        id: :room_bedroom
      ),
      Supervisor.child_spec(
        {Room.Controller,
         [
           :hass,
           [name: "living", input: {InputDriver.Ikea5Btn, ["sensor.living_remote_action"], nil}]
         ]},
        id: :room_living
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
