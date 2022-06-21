defmodule InputDriver.IkeaMotionSensor do
  use GenServer
  require Logger

  ## Client API

  def start([mqtt, entity_id | opts]) do
    GenServer.start(__MODULE__, {mqtt, entity_id, self()}, opts)
  end

  def start_link([mqtt, entity_id | opts]) do
    GenServer.start_link(__MODULE__, {mqtt, entity_id, self()}, opts)
  end

  ## GenServer Callbacks

  @impl true
  def init({mqtt, entity_id, subscriber}) do
    topic = "zigbee2mqtt/#{entity_id}"

    case Mqtt.subscribe(mqtt, [{topic, []}]) do
      {:ok, _props, _reason_codes} ->
        ref = Process.monitor(mqtt)
        {:ok, %{subscriber: subscriber, topic: topic, entity_id: entity_id, mqtt: {ref, mqtt}}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:mqtt, topic, payload}, state) when topic == state.topic do
    if JSON.decode!(payload)["occupancy"] do
      Logger.debug(fn -> "[#{state.entity_id}] detected motion" end)
      send(state.subscriber, {__MODULE__, self(), :sensor_active})
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _which, reason}, state)
      when ref == elem(state.mqtt, 0) do
    {:stop, {:mqtt_down, reason}, state}
  end
end
