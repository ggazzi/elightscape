defmodule Room.StateMachine do
  use GenServer
  require Logger

  ## Client API

  def start(opts) do
    GenServer.start(__MODULE__, :ok, opts)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def send_event(machine, event) do
    GenServer.call(machine, event)
  end

  ## GenServer Callbacks

  @impl true
  def init(:ok) do
    {:ok, %{:lights_on => false, :listening_to_sensor => false}}
  end

  @impl true
  def handle_call(event, _target, state) do
    new_state = react_to_event(event, state)
    output = react_to_state_change(state, new_state)
    Logger.info(fn -> "#{inspect(output)} -> #{inspect(new_state)}" end)
    {:reply, output, new_state}
  end

  def react_to_event(:toggle, state) do
    if state[:lights_on] do
      %{state | :lights_on => false, :listening_to_sensor => false}
    else
      %{state | :lights_on => true, :listening_to_sensor => true}
    end
  end

  def react_to_event(:always_on, state) do
    %{state | :lights_on => true, :listening_to_sensor => false}
  end

  def react_to_event(:always_off, state) do
    %{state | :lights_on => false, :listening_to_sensor => false}
  end

  def react_to_event(:sensor_active, state) do
    if state[:listening_to_sensor] do
      %{state | :lights_on => true}
    else
      state
    end
  end

  def react_to_event(:sensor_timeout, state) do
    if state[:listening_to_sensor] do
      %{state | :lights_on => false}
    else
      state
    end
  end

  def react_to_event(unknown, state) do
    Logger.warn(fn -> "Unknown event #{inspect(unknown)}" end)
    state
  end

  def react_to_state_change(curr, next) do
    if curr.lights_on != next.lights_on do
      {:set_lights, next.lights_on}
    else
    end
  end
end
