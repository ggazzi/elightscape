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
    send(controller, {__MODULE__, :register, self()})

    {:ok, {config, state}}
  end

  @impl true
  def handle_cast(event, {config, state}) do
    new_state = react_to_event(event, state)

    effects = determine_effects(config, state, new_state)
    Logger.info(fn -> "#{inspect(effects)} -> #{inspect(new_state)}" end)

    if effects != nil do
      send(config.controller, {__MODULE__, :effect, effects})
    end

    case determine_timeout(config, new_state) do
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

  @doc """
  Determine which effects are necessary to transition from the current state into the next.

  These effects should be sent to the controller, which will interpret them.
  If no effects are necessary, produces `nil`.
  """
  def determine_effects(_config, curr, next) do
    if curr.lights_on != next.lights_on do
      {:set_lights, next.lights_on}
    end
  end

  @doc """
  Determine which timeout is required by the given state.

  If a timeout is necessary returns a pair `{timeout, event}`, stating that the
  given `event` should be processed by `react_to_event` after the timeout.
  Otherwise, returnis `nil`.
  """
  def determine_timeout(
        config,
        %{
          lights_on: lights_on,
          listening_to_sensor: listening_to_sensor
        } = _state
      ) do
    if lights_on and listening_to_sensor do
      # Any event will reset the sensor timeout
      {config.sensor_timeout, :sensor_timeout}
    end
  end

  @doc """
  Update the state according to the current state and an event received from the controller.

  This will only change the internal state, external effects will be handled by other functions.
  """
  def react_to_event({:toggle, :click, 1}, state) do
    # Toggles between always-off and sensor-on
    if state.lights_on do
      %{state | lights_on: false, listening_to_sensor: false}
    else
      %{state | lights_on: true, listening_to_sensor: true}
    end
  end

  def react_to_event({:toggle, :click, 2}, state) do
    # Sets to always-on
    %{state | lights_on: true, listening_to_sensor: false}
  end

  def react_to_event({:toggle, :click, 3}, state) do
    # Sets to sensor-off
    %{state | lights_on: false, listening_to_sensor: true}
  end

  def react_to_event({:on, :click, 1}, state) do
    # Sets to sensor-on
    %{state | lights_on: true, listening_to_sensor: true}
  end

  def react_to_event({:on, :click, 2}, state) do
    # Sets to always-on
    %{state | lights_on: true, listening_to_sensor: false}
  end

  def react_to_event({:off, :click, 1}, state) do
    # Sets to always-off
    %{state | lights_on: false, listening_to_sensor: false}
  end

  def react_to_event({:off, :click, 2}, state) do
    # Sets to sensor-off
    %{state | lights_on: false, listening_to_sensor: true}
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
end
