defmodule Room.StateMachine do
  use GenServer
  require Logger

  ## Client API

  def start([controller, config | opts]) do
    GenServer.start(__MODULE__, {controller, config}, opts)
  end

  def start_link([controller, config | opts]) do
    GenServer.start_link(__MODULE__, {controller, config}, opts)
  end

  def send_event(machine, event) do
    GenServer.cast(machine, event)
  end

  ## GenServer Callbacks

  @default_sensor_timeout 5 * 60 * 1000

  @impl true
  def init({controller, config}) do
    config = %{
      controller: controller,
      sensor_timeout: Keyword.get(config, :sensor_timeout, @default_sensor_timeout)
    }

    state = %{lights_on: false, listening_to_sensor: false}

    {:ok, {config, state}}
  end

  @impl true
  def handle_cast(event, {config, state}) do
    new_state = react_to_event(event, state)
    {output, timeout} = react_to_state_change(config, state, new_state)
    Logger.info(fn -> "#{inspect(output)} -> #{inspect(new_state)}" end)

    send(config.controller, {__MODULE__, output})

    case timeout do
      nil ->
        {:noreply, {config, Map.delete(new_state, :timeout_event)}}

      {timeout, event} ->
        {:noreply, {config, Map.put(new_state, :timeout_event, event)}, timeout}
    end
  end

  @impl true
  def handle_info(:timeout, {config, state}) when state.timeout_event != nil do
    handle_cast(state.timeout_event, {config, state})
  end

  def react_to_event({:toggle, :click}, state) do
    if state.lights_on do
      %{state | lights_on: false, listening_to_sensor: false}
    else
      %{state | lights_on: true, listening_to_sensor: true}
    end
  end

  def react_to_event({:on, :click}, state) do
    %{
      state
      | lights_on: true,
        listening_to_sensor: state.listening_to_sensor or not state.lights_on
    }
  end

  def react_to_event({:off, :click}, state) do
    %{state | lights_on: false, listening_to_sensor: false}
  end

  def react_to_event(:always_on, state) do
    %{state | lights_on: true, listening_to_sensor: false}
  end

  def react_to_event(:always_off, state) do
    %{state | lights_on: false, listening_to_sensor: false}
  end

  def react_to_event(:sensor_active, state) do
    if state.listening_to_sensor do
      %{state | lights_on: true}
    else
      state
    end
  end

  def react_to_event(:sensor_timeout, state) do
    if state.listening_to_sensor do
      %{state | lights_on: false}
    else
      state
    end
  end

  def react_to_event(unknown, state) do
    Logger.warn(fn -> "Unknown event #{inspect(unknown)}" end)
    state
  end

  def react_to_state_change(config, curr, next) do
    if curr.lights_on != next.lights_on do
      timeout =
        if next.lights_on and next.listening_to_sensor do
          {config.sensor_timeout, :sensor_timeout}
        end

      {{:set_lights, next.lights_on}, timeout}
    else
      {nil, nil}
    end
  end
end
