defmodule Room.Controller do
  use GenServer
  require Logger

  defmodule Supervisor do
    use Elixir.Supervisor

    def start_link({_, _, config} = init_arg) do
      Supervisor.start_link(__MODULE__, init_arg,
        name: :"Room.#{Keyword.get(config, :name)}.Supervisor"
      )
    end

    @impl true
    def init({hass, mqtt, config}) do
      room_name = Keyword.get(config, :name)
      supervisor_name = :"Room.#{room_name}.DynamicSupervisor"

      children = [
        {DynamicSupervisor, name: supervisor_name, strategy: :one_for_one},
        {Room.Controller,
         [{hass, mqtt, supervisor_name, config}, name: :"Room.#{room_name}.Controller"]}
      ]

      # If either the controller or the supervisor die, the other one cannot work anymore
      Supervisor.init(children, strategy: :one_for_all)
    end
  end

  ## Client API

  def start([init_args | opts]) do
    GenServer.start(__MODULE__, init_args, opts)
  end

  def start_link([init_args | opts]) do
    GenServer.start_link(__MODULE__, init_args, opts)
  end

  ## Server Callbacks

  def init({hass, mqtt, supervisor, config}) do
    name = config[:name]

    {:ok, machine} =
      DynamicSupervisor.start_child(
        supervisor,
        {Room.StateMachine, [self(), config, name: :"Room.#{name}.StateMachine"]}
      )

    for {:light, entity_id} <- config do
      DynamicSupervisor.start_child(supervisor, {Room.Light, [hass, self(), entity_id]})
    end

    for {:input, {module, opts}} <- config do
      DynamicSupervisor.start_child(
        supervisor,
        {module, [hass: hass, mqtt: mqtt, subscriber: self()] ++ opts}
      )
    end

    {:ok,
     %{
       machine: machine,
       input_drivers: %{},
       lights: MapSet.new(),
       hass: hass,
       mqtt: mqtt,
       scene_on: "scene.#{name}_high_night",
       scene_off: "scene.#{name}_off"
     }}
  end

  def handle_info({Room.StateMachine, :register, machine}, state) do
    {:noreply, %{state | machine: machine}}
  end

  def handle_info({Room.StateMachine, :effect, effect}, state) do
    handle_effect(effect, state)
    {:noreply, state}
  end

  def handle_info({Room.Light, :register, pid}, %{lights: lights} = state) do
    # We don't need to store the monitor ref, as we will not stop monitoring the light process
    Process.monitor(pid)
    lights = MapSet.put(lights, pid)
    {:noreply, %{state | lights: lights}}
  end

  def handle_info({Room.Light, entity_id, :turned_on, on?}, state) do
    Room.StateMachine.send_event(state.machine, {:turned_on, entity_id, on?})
    {:noreply, state}
  end

  def handle_info({InputDriver, pid, :register}, %{input_drivers: input_drivers} = state) do
    ref = Process.monitor(pid)
    input_drivers = Map.put(input_drivers, pid, ref)
    {:noreply, %{state | input_drivers: input_drivers}}
  end

  def handle_info({InputDriver, pid, event}, state) do
    case state.input_drivers[pid] do
      nil ->
        Logger.warn(fn -> "[#{inspect(pid)}] unknown input driver #{inspect(event)}" end)
        {:noreply, state}

      _ref ->
        Room.StateMachine.send_event(state.machine, event)
        Logger.debug(fn -> "[#{inspect(pid)}] #{inspect(event)}" end)
        {:noreply, state}
    end
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %{input_drivers: input_drivers, lights: lights} = state
      ) do
    cond do
      input_drivers[pid] ->
        {:noreply, %{state | input_drivers: Map.delete(input_drivers, pid)}}

      MapSet.member?(lights, pid) ->
        {:noreply, %{state | lights: MapSet.delete(lights, pid)}}
    end
  end

  defp handle_effect({:set_lights, on}, state) do
    scene =
      if on do
        state.scene_on
      else
        state.scene_off
      end

    Task.start(fn ->
      {:ok, _} = Hass.call_service(state.hass, :scene, :turn_on, target: %{entity_id: scene})
    end)
  end

  defp handle_effect(:commit_lights, state) do
    for light <- state.lights do
      Room.Light.commit_if_temporarily_off(light)
    end
  end
end
