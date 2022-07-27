defmodule Elightscape do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    case connect() do
      {:ok, _} -> {:ok, self()}
      {:error, e} -> {:error, e}
      :ignore -> {:error, :ignore}
    end
  end

  def connect do
    connect(config())
  end

  def connect(config) do
    {:ok, mqtt_pid} = Mqtt.start_link(config[:mqtt], [])
    Process.register(mqtt_pid, :mqtt)

    Elightscape.Supervisor.start_link(config, name: Elightscape.Supervisor)
  end

  defp config do
    [hass: hass_config(), mqtt: Application.fetch_env!(:elightscape, :mqtt)]
  end

  defp hass_config do
    if Application.fetch_env!(:elightscape, :hass_plugin) do
      [plugin: true]
    else
      [
        host: Application.fetch_env!(:elightscape, :hass_host),
        port: Application.fetch_env!(:elightscape, :hass_port),
        token: Application.fetch_env!(:elightscape, :hass_token)
      ]
    end
  end
end
