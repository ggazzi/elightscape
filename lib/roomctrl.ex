defmodule RoomCtrl do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    case RoomCtrl.connect() do
      {:ok, _} -> {:ok, self()}
      {:error, e} -> {:error, e}
      :ignore -> {:error, :ignore}
    end
  end

  def connect do
    connect(config())
  end

  def connect(config) do
    RoomCtrl.Supervisor.start_link(config, name: RoomCtrl.Supervisor)
  end

  defp config do
    [hass: hass_config(), mqtt: Application.fetch_env!(:roomctrl, :mqtt)]
  end

  defp hass_config do
    if Application.fetch_env!(:roomctrl, :hass_plugin) do
      [plugin: true]
    else
      [
        host: Application.fetch_env!(:roomctrl, :hass_host),
        port: Application.fetch_env!(:roomctrl, :hass_port),
        token: Application.fetch_env!(:roomctrl, :hass_token)
      ]
    end
  end
end