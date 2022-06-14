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
      {Room.Controller, [:hass]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
