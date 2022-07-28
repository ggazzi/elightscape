defmodule InputDriver.Ikea.RemoteTradfri do
  use GenServer
  require Logger

  @click_cooldown 300

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

        {:ok,
         %{
           curr_held: nil,
           curr_click: nil,
           topic: topic,
           subscriber: subscriber,
           mqtt: {ref, mqtt}
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(
        {:mqtt, topic, payload},
        %{curr_held: curr_held, curr_click: curr_click} = state
      )
      when topic == state.topic do
    case decode_action(payload) do
      {button, :hold} = action when curr_held == nil ->
        send_action(state, action)
        {:noreply, %{state | curr_held: button, curr_click: nil}}

      {^curr_held, :release} = action ->
        send_action(state, action)
        {:noreply, %{state | curr_held: nil, curr_click: nil}}

      {button, :click} ->
        case curr_click do
          nil ->
            {:noreply, %{state | curr_click: {button, 1}}, @click_cooldown}

          {^button, n} ->
            {:noreply, %{state | curr_click: {button, n + 1}}, @click_cooldown}

          {other_button, n} ->
            send_action(state, {other_button, :click, n})
            {:noreply, %{state | curr_click: {button, 1}}, @click_cooldown}
        end
    end
  end

  def handle_info(:timeout, %{curr_click: curr_click} = state) do
    case curr_click do
      {button, n} -> send_action(state, {button, :click, n})
      nil -> nil
    end

    {:noreply, %{state | curr_click: nil}}
  end

  def handle_info({:DOWN, ref, :process, _which, reason}, state)
      when ref == elem(state.mqtt, 0) do
    {:stop, {:mqtt_down, reason}, state}
  end

  @impl true
  def terminate(reason, %{curr_held: curr_held, curr_click: curr_click} = state) do
    case curr_click do
      {button, n} ->
        send_action(state, {button, :click, n})

      nil ->
        nil
    end

    if curr_held != nil do
      send_action(state, {curr_held, :release})
    end

    {:stop, reason}
  end

  defp send_action(%{subscriber: subscriber}, action) do
    send(subscriber, {__MODULE__, self(), action})
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
