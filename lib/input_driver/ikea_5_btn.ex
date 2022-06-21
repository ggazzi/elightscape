defmodule InputDriver.Ikea5Btn do
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
    topic = "zigbee2mqtt/#{entity_id}/action"

    case Mqtt.subscribe(mqtt, [{topic, []}]) do
      {:ok, _props, _reason_codes} ->
        ref = Process.monitor(mqtt)
        {:ok, %{button: nil, topic: topic, subscriber: subscriber, mqtt: {ref, mqtt}}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:mqtt, topic, payload}, state) when topic == state.topic do
    new_button = decode_action(payload)

    if new_button != nil do
      send(state.subscriber, {__MODULE__, self(), new_button})
    end

    {:noreply, %{state | button: new_button}}
  end

  def handle_info({:DOWN, ref, :process, _which, reason}, state)
      when ref == elem(state.mqtt, 0) do
    {:stop, {:mqtt_down, reason}, state}
  end

  def decode(payload) do
    data = JSON.decode!(payload)
    decode_action(data["action"])
  end

  def decode_action(action) do
    case action do
      "" -> nil
      "toggle" -> :toggle
      _ -> action
    end
  end
end
