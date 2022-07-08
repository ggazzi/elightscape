defmodule InputDriver.Ikea5Btn do
  use GenServer
  require Logger

  ## Client API

  def start([mqtt, subscriber, entity_id | opts]) do
    GenServer.start(__MODULE__, {mqtt, subscriber, entity_id}, opts)
  end

  def start_link([mqtt, subscriber, entity_id | opts]) do
    GenServer.start_link(__MODULE__, {mqtt, subscriber, entity_id}, opts)
  end

  ## GenServer Callbacks

  # def child_spec(opts) do
  #   %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  # end

  @impl true
  def init({mqtt, subscriber, entity_id}) do
    # FIXME: remove hardcoded MQTT topic prefix
    topic = "zigbee/#{entity_id}/action"

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
    send(state.subscriber, {__MODULE__, self(), decode_action(payload)})
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _which, reason}, state)
      when ref == elem(state.mqtt, 0) do
    {:stop, {:mqtt_down, reason}, state}
  end

  defp decode_action(action) do
    case action do
      "toggle" -> {:toggle, :click}
      "toggle_hold" -> {:toggle, :hold}
      "arrow_right_click" -> {:arrow_right, :click}
      "arrow_right_hold" -> {:arrow_right, :hold}
      "arrow_right_release" -> {:arrow_right, :release}
      "arrow_left_click" -> {:arrow_left, :click}
      "arrow_left_hold" -> {:arrow_left, :hold}
      "arrow_left_release" -> {:arrow_left, :release}
      "brightness_up_click" -> {:brightness_up, :click}
      "brightness_up_hold" -> {:brightness_up, :hold}
      "brightness_up_release" -> {:brightness_up, :release}
      "brightness_down_click" -> {:brightness_down, :click}
      "brightness_down_hold" -> {:brightness_down, :hold}
      "brightness_down_release" -> {:brightness_down, :release}
    end
  end
end
