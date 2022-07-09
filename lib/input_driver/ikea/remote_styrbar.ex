defmodule InputDriver.Ikea.RemoteStyrbar do
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

  @impl true
  def init({mqtt, subscriber, entity_id}) do
    # FIXME: remove hardcoded MQTT topic prefix
    topic = "zigbee/#{entity_id}/action"

    case Mqtt.subscribe(mqtt, topic) do
      :ok ->
        ref = Process.monitor(mqtt)
        {:ok, %{curr_pressed: nil, topic: topic, subscriber: subscriber, mqtt: {ref, mqtt}}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:mqtt, topic, payload}, state) when topic == state.topic do
    button = decode_action(payload, state.curr_pressed)

    curr_pressed =
      case button do
        {btn, :hold} -> btn
        _ -> nil
      end

    send(state.subscriber, {__MODULE__, self(), button})

    {:noreply, %{state | curr_pressed: curr_pressed}}
  end

  def handle_info({:DOWN, ref, :process, _which, reason}, state)
      when ref == elem(state.mqtt, 0) do
    {:stop, {:mqtt_down, reason}, state}
  end

  defp decode_action(action, curr_pressed) do
    case action do
      "on" ->
        {:on, :click}

      "off" ->
        {:off, :click}

      "arrow_right_click" ->
        {:arrow_right, :click}

      "arrow_right_hold" ->
        {:arrow_right, :hold}

      "arrow_right_release" ->
        {:arrow_right, :release}

      "arrow_left_click" ->
        {:arrow_left, :click}

      "arrow_left_hold" ->
        {:arrow_left, :hold}

      "arrow_left_release" ->
        {:arrow_left, :release}

      "brightness_move_up" ->
        {:brightness_up, :hold}

      "brightness_move_down" ->
        {:brightness_down, :hold}

      "brightness_stop" when curr_pressed == :brightness_up or curr_pressed == :brightness_down ->
        {curr_pressed, :release}
    end
  end
end
