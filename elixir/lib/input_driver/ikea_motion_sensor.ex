defmodule InputDriver.IkeaMotionSensor do
  use GenServer
  require Logger

  ## Client API

  def start([hass, subscriber, entity_id | opts]) do
    GenServer.start(__MODULE__, {hass, entity_id, subscriber}, opts)
  end

  def start_link([hass, subscriber, entity_id | opts]) do
    GenServer.start_link(__MODULE__, {hass, entity_id, subscriber}, opts)
  end

  ## GenServer Callbacks

  @impl true
  def init({hass, entity_id, subscriber}) do
    {:ok, id} =
      Hass.Connection.subscribe_trigger(hass, %{platform: :state, entity_id: entity_id, to: nil})

    {:ok, %{subscriber: subscriber, hass_sub: id, entity_id: entity_id}}
  end

  @impl true
  def handle_info({:hass, id, {:event, event}}, state) when id == state.hass_sub do
    if event["variables"]["trigger"]["to_state"]["attributes"]["occupancy"] do
      Logger.debug(fn -> "[#{state.entity_id}] detected motion" end)
      send(state.subscriber, {__MODULE__, self(), :sensor_active})
    end

    {:noreply, state}
  end
end
